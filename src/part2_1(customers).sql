/*
Представление Клиенты

Поле	                                        Название поля в системе	        Формат / возможные значения	        Описание
Идентификатор клиента	                        Customer_ID	                    ---	                                Уникальное значение
Значение среднего чека	                        Customer_Average_Check	        Арабская цифра, десятичная дробь	Значение среднего чека клиента в рублях за анализируемый период
Сегмент по среднему чеку	                    Customer_Average_Check_Segment	Высокий; Средний; Низкий	        Описание сегмента
Значение частоты транзакций	                    Customer_Frequency	            Арабская цифра, десятичная дробь	Значение частоты визитов клиента в среднем количестве дней между транзакциями. Также учитывается время, т.е. результатом может быть не целое число
Сегмент по частоте транзакций	                Customer_Frequency_Segment	    Часто; Средне; Редко	            Описание сегмента
Количество дней после предыдущей транзакции	    Customer_Inactive_Period	    Арабская цифра, десятичная дробь	Количество дней, прошедших с даты предыдущей транзакции клиента. Также учитывается время, т.е. результатом может быть не целое число
Коэффициент оттока	                            Customer_Churn_Rate	            Арабская цифра, десятичная дробь	Значение коэффициента оттока клиента
Сегмент по коэффициенту оттока	                Customer_Churn_Segment	        Высокий; Средний; Низкий	        Описание сегмента
Номер сегмента	                                Customer_Segment	            Арабская цифра	                    Номер сегмента, к которому принадлежит клиент
Идентификатор основного магазина	            Customer_Primary_Store	        ---	                                ---
*/

DROP VIEW IF EXISTS Customers_View;
CREATE VIEW Customers_View AS 

----------------------------- Предварительные запросы, перменные и таблицы -----------------------------

-- максимальное значение среднего чека для процентной градации
WITH max_avg_check AS (
  SELECT 
    MAX(Customer_Average_Check) AS max_avg_check_value
  FROM (
    SELECT 
      SUM(Transaction_Summ) / COUNT(t.Transaction_ID) AS Customer_Average_Check
    FROM personalinformation p
    JOIN cards c ON c.customer_id = p.customer_id
    JOIN transactions t ON t.Customer_Card_ID = c.Customer_Card_ID
    GROUP BY p.Customer_ID
  ) AS max_avg_check
),

-- максимальное значение интенсивности транзакций для процентной градации
max_inactive_period AS (
  SELECT 
    MAX(inactive_period_value)
  FROM (	
  SELECT 
    EXTRACT(DAY FROM ( MAX(Transaction_DateTime) - MIN(Transaction_DateTime)))/ COUNT(t.Transaction_ID) AS inactive_period_value
    FROM personalinformation p
    JOIN cards c ON c.customer_id = p.customer_id
    JOIN transactions t ON t.Customer_Card_ID = c.Customer_Card_ID
    GROUP BY p.Customer_ID
  ) AS max_inactive_period_value
),

-- определение основного магазина клиента
-- создаем таблицу с процентным соотношением транзакций для каждого магазина клиента 
-- указываем последнюю дату транзакции для каждого магазина
Customer_Primary_Store_Set AS (
	SELECT
	  Customer_ID,
	  Transaction_Store_ID,
	  ((TransactionCount * 100.0) / TotalTransactionCount) AS TransactionPercentage,
		(SELECT MAX(Transaction_DateTime) 
		 FROM Transactions t
		 JOIN Cards c ON c.Customer_Card_ID = t.Customer_Card_ID
		 WHERE cnt.Transaction_Store_ID = t.Transaction_Store_ID
		AND c.Customer_ID = cnt.Customer_ID) AS last_transaction
	FROM (
-- вычисляем общее количество транзакций для каждого клиента Customer_Number_Transactions
		SELECT
			Customer_ID,
			Transaction_Store_ID,
			COUNT(Transaction_ID) AS TransactionCount,
			SUM(COUNT(Transaction_ID)) OVER (PARTITION BY Customer_ID) AS TotalTransactionCount
		  FROM Transactions
		  JOIN Cards c ON c.Customer_Card_ID = Transactions.Customer_Card_ID
			GROUP BY Customer_ID, transaction_store_id
		 ) AS cnt -- Customer_Number_Transactions
	ORDER BY Customer_ID, Transaction_Store_ID
),

--  определение магазина, в котором клиент совершил три предыдущие транзакции
loyal_customers AS (
	SELECT Customer_ID
	FROM (
		SELECT
		  Customer_ID,
		  Transaction_Store_ID
		FROM (
--  для каждого клиента и каждого магазина упорядочиваем транзакции по убыванию времени
			SELECT
				Customer_ID,
				Transaction_Store_ID,
				Transaction_DateTime,
				ROW_NUMBER() OVER (PARTITION BY Customer_ID ORDER BY Transaction_DateTime DESC) AS rn
		  FROM Transactions
		  JOIN Cards c ON c.Customer_Card_ID = Transactions.Customer_Card_ID) AS recent_transactions
	WHERE rn <= 3) recent_transactions -- выбираем строки, где номер строки меньше или равен 3 - последние визиты
	GROUP BY Customer_ID
	HAVING COUNT(DISTINCT Transaction_Store_ID) = 1
),

-- Собираем предварительные данные которые далее проще привести к необходимому виду в виде таблицы spec_1
-- Средний чек, группируем, интенсивности транзакций, группируем, количество дней после самой поздней транзакции
spec_1 AS (
SELECT 
  p.customer_id AS Customer_ID,
--   Рассчет среднего чека - суммируем все транзакции по всем картам клиента и делим на транзакций количество
  SUM(Transaction_Summ)/COUNT(t.Transaction_ID) AS Customer_Average_Check,
-- 	Вычисляем процентную градацию для полседующего вычисления группы High/Medium/Low
  ROUND(SUM(Transaction_Summ)/COUNT(t.Transaction_ID)* 100 / mc.max_avg_check_value, 0 ) AS Customer_Average_Check_Percentage,
-- 	Определение интенсивности транзакций из даты самой поздней вычитается дата самой ранней транзакции (day)  
  EXTRACT(DAY FROM ( MAX(Transaction_DateTime) - MIN(Transaction_DateTime)))/ COUNT(t.Transaction_ID) AS Customer_Frequency,
-- 	Определение сегмента - сегментируем для полседующего вычисления группы Often/Occasionally/Rarely
  ROUND(EXTRACT(DAY FROM (MAX(Transaction_DateTime) - MIN(Transaction_DateTime)))/ COUNT(t.Transaction_ID)* 100 / mp.max, 0) AS Customer_Frequency_Percentage,
-- 	Определение периода после предыдущей транзакции необходимо определить количество дней после самой поздней транзакции
  EXTRACT(EPOCH FROM (SELECT * FROM dateanalysisformation) - MAX(Transaction_DateTime)) / 86400.0  AS Customer_Inactive_Period
FROM personalinformation p
JOIN cards c ON c.customer_id = p.customer_id
JOIN transactions t ON t.Customer_Card_ID = c.Customer_Card_ID
CROSS JOIN max_avg_check mc
CROSS JOIN max_inactive_period mp
GROUP BY p.Customer_ID, mc.max_avg_check_value, mp.max
),

-- данные из прошлого запроса к нужному виду - на основе процентной градации выводим название группы в таблицу spec_2 + коэффициент оттока клиентов
spec_2  AS (
SELECT 
    Customer_ID,
    Customer_Average_Check,
    CASE
-- 	конвертируем полученные данные для вывода верного ответа группы High/Medium/Low
      WHEN Customer_Average_Check_Percentage <= 65 THEN 'Low'
      WHEN Customer_Average_Check_Percentage <= 90 THEN 'Medium'
      ELSE 'High'
    END AS Customer_Average_Check_Segment,
	Customer_Frequency,
	CASE
-- 	конвертируем полученные данные для вывода верного ответа группы Often/Occasionally/Rarely
      WHEN Customer_Frequency_Percentage <= 10 THEN 'Often'
      WHEN Customer_Frequency_Percentage <= 35 THEN 'Occasionally'
      ELSE 'Rarely'
    END AS Customer_Frequency_Segment,
	Customer_Inactive_Period,
-- 	вычисляем коэффициент оттока клиентов 
	Customer_Inactive_Period / Customer_Frequency AS Customer_Churn_Rate,
	CASE
-- 	конвертируем полученные данные для вывода верного ответа группы High/Medium/Low
      WHEN Customer_Inactive_Period / Customer_Frequency <= 2  THEN 'Low'
      WHEN Customer_Inactive_Period / Customer_Frequency <= 5  THEN 'Medium'
      ELSE 'High'
    END AS Customer_Churn_Segment
FROM spec_1
ORDER BY Customer_ID
)

-------------------------------------------- Итоговый запрос --------------------------------------------

	SELECT 
		spec_2.Customer_ID,
		Customer_Average_Check,
		Customer_Average_Check_Segment,
		Customer_Frequency,
		Customer_Frequency_Segment,
		Customer_Inactive_Period,
		Customer_Churn_Rate,
		Customer_Churn_Segment,
		
-- 		Присвоение номера сегмента. На основании комбинации значений клиента в полях 
-- 		Customer_Average_Check_Segment, Customer_Frequency_Segment и Customer_Churn_Segment 
-- 		таблицы Клиенты клиенту присваивается номер сегмента в соответствии с таблицей из задания
(CASE
			WHEN Customer_Average_Check_Segment = 'Low' THEN
				CASE
					WHEN Customer_Frequency_Segment = 'Rarely' THEN 
						CASE
							WHEN Customer_Churn_Segment = 'Low' THEN 1
							WHEN Customer_Churn_Segment = 'Medium' THEN 2
							WHEN Customer_Churn_Segment = 'High' THEN 3
						END
					WHEN Customer_Frequency_Segment = 'Occasionally' THEN
						CASE
							WHEN Customer_Churn_Segment = 'Low' THEN 4
							WHEN Customer_Churn_Segment = 'Medium' THEN 5
							WHEN Customer_Churn_Segment = 'High' THEN 6
						END
					WHEN Customer_Frequency_Segment = 'Often' THEN
						CASE
							WHEN Customer_Churn_Segment = 'Low' THEN 7
							WHEN Customer_Churn_Segment = 'Medium' THEN 8
							WHEN Customer_Churn_Segment = 'High' THEN 9
						END
				END
			WHEN Customer_Average_Check_Segment = 'Medium' THEN
				CASE
					WHEN Customer_Frequency_Segment = 'Rarely' THEN
						CASE
							WHEN Customer_Churn_Segment = 'Low' THEN 10
							WHEN Customer_Churn_Segment = 'Medium' THEN 11
							WHEN Customer_Churn_Segment = 'High' THEN 12
						END
					WHEN Customer_Frequency_Segment = 'Occasionally' THEN
						CASE
							WHEN Customer_Churn_Segment = 'Low' THEN 13
							WHEN Customer_Churn_Segment = 'Medium' THEN 14
							WHEN Customer_Churn_Segment = 'High' THEN 15
						END
					WHEN Customer_Frequency_Segment = 'Often' THEN
						CASE
							WHEN Customer_Churn_Segment = 'Low' THEN 16
							WHEN Customer_Churn_Segment = 'Medium' THEN 17
							WHEN Customer_Churn_Segment = 'High' THEN 18
						END
				END
			WHEN Customer_Average_Check_Segment = 'High' THEN
				CASE
					WHEN Customer_Frequency_Segment = 'Rarely' THEN
						CASE
							WHEN Customer_Churn_Segment = 'Low' THEN 19
							WHEN Customer_Churn_Segment = 'Medium' THEN 20
							WHEN Customer_Churn_Segment = 'High' THEN 21
						END
					WHEN Customer_Frequency_Segment = 'Occasionally' THEN
						CASE
							WHEN Customer_Churn_Segment = 'Low' THEN 22
							WHEN Customer_Churn_Segment = 'Medium' THEN 23
							WHEN Customer_Churn_Segment = 'High' THEN 24
						END
					WHEN Customer_Frequency_Segment = 'Often' THEN
						CASE
							WHEN Customer_Churn_Segment = 'Low' THEN 25
							WHEN Customer_Churn_Segment = 'Medium' THEN 26
							WHEN Customer_Churn_Segment = 'High' THEN 27
						END
				END
		END) AS Customer_Segment,
		(CASE
-- Если покупатель входит в список тех кто последние три покупки совершал в одном магазине - к списку лояльных клиентов
			WHEN spec_2.Customer_ID = (SELECT Customer_ID FROM loyal_customers) THEN 
		 		(SELECT
				  Transaction_Store_ID
				FROM (
-- нумеруем транзакции начиная с последней
					SELECT
						Customer_ID,
						Transaction_Store_ID,
						Transaction_DateTime,
						ROW_NUMBER() OVER (PARTITION BY Customer_ID ORDER BY Transaction_DateTime DESC) AS rn
				  	FROM Transactions
				  	JOIN Cards c ON c.Customer_Card_ID = Transactions.Customer_Card_ID) AS latest_transaction_data
-- получаем последнюю транзакцию данного клиента и получаем id магазина
				WHERE rn = 1 AND latest_transaction_data.Customer_ID = spec_2.Customer_ID)
-- Если покупатель не входит в список тех кто последние три покупки совершал в одном магазине
-- находим магазин, в котором совершена наибольшая доля всех транзакций клиента
		 ELSE
			(
				SELECT Transaction_Store_ID 
				FROM Customer_Primary_Store_Set cpss
				WHERE cpss.Customer_ID = spec_2.Customer_ID
				AND TransactionPercentage = (
					SELECT MAX(TransactionPercentage) AS bigest --Выбираем магазин куда покупатель ходит чаще всего
					FROM Customer_Primary_Store_Set cpss
					WHERE cpss.Customer_ID = spec_2.Customer_ID
					)
				AND last_transaction = (  -- Если таких магазинов несколько то из них
					SELECT MAX(last_transaction) -- получаем магазин с датой последней транзакции
					FROM Customer_Primary_Store_Set cpss
					WHERE cpss.Customer_ID = spec_2.Customer_ID
					AND TransactionPercentage = ( 
						SELECT MAX(TransactionPercentage) AS bigest
						FROM Customer_Primary_Store_Set cpss
						WHERE cpss.Customer_ID = spec_2.Customer_ID)))

		END) AS Customer_Primary_Store
	FROM spec_2
	FULL JOIN loyal_customers ON loyal_customers.Customer_ID = spec_2.Customer_ID;
	
SELECT * FROM Customers_View