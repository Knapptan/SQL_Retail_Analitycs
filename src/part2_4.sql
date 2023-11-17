/*
Представление Группы
Поле	                    Название поля в системе	    Формат / возможные значения	        Описание
Идентификатор клиента	    Customer_ID	                ---	                                ---
Идентификатор группы	    Group_ID	                ---	                                ---
Индекс востребованности	    Group_Affinity_Index	    Арабская цифра, десятичная дробь	Коэффициент востребованности данной группы клиентом
Индекс оттока	            Group_Churn_Rate	        Арабская цифра, десятичная дробь	Индекс оттока клиента по конкретной группе
Индекс стабильности	        Group_Stability_Index	    Арабская цифра, десятичная дробь	Показатель, демонстрирующий стабильность потребления группы клиентом
Актуальная маржа по группе	Group_Margin	            Арабская цифра, десятичная дробь	Показатель актуальной маржи по группе для конкретного клиента
Доля транзакций со скидкой	Group_Discount_Share	    Арабская цифра, десятичная дробь	Доля транзакций по покупке группы клиентом, в рамках которых были применена скидка (без учета списания бонусов программы лояльности)
Минимальный размер скидки	Group_Minimum_Discount	    Арабская цифра, десятичная дробь	Минимальный размер скидки, зафиксированный для клиента по группе
Средний размер скидки	    Group_Average_Discount	    Арабская цифра, десятичная дробь	Средний размер скидки по группе для клиента
*/



-- DROP VIEW IF EXISTS Groups_view;
CREATE OR REPLACE VIEW Groups_View AS
WITH group_list AS 
				(
	
					SELECT Customer_ID, Group_ID 
					FROM purchase_history_view
					GROUP BY Customer_ID, Group_ID -- Дедубликация
					ORDER BY Customer_ID, Group_ID

				),
Affinity_Index AS  -- Расчет востребованности

/* Определение общего количества транзакций клиента. Определяется
общее количество транзакций клиента, совершенных им между первой и
последней транзакциями с анализируемой группой (включая транзакции,
в рамках которых не было анализируемой группы), включая первую и
последнюю транзакции с группой. Для этого подсчитывается количество
уникальных значений в поле Transaction_ID таблицы История покупок,
дата совершения транзакций для которых больше или равна
дате первой транзакции клиента с группой (значение поля
First_Group_Purchase_Date таблицы Периоды) и меньше или
равна дате последней транзакции клиента с группой (значение поля
Last_Group_Purchase_Date таблицы Периоды).


Расчет индекса востребованности группы. Количество транзакций с
анализируемой группой (значение поля Group_Purchase таблицы Периоды) 
делится на общее количество транзакций клиента,
совершенных с первой по последнюю транзакции, в которых была
анализируемая группа. Итоговое значение
сохраняется для группы в поле Group_Affinity_Index таблицы Группы.
*/
				(
				SELECT gl.Customer_ID,gl.Group_ID, (pv.Group_Purchase::FLOAT / COUNT(phv.Transaction_ID)) AS Group_Affinity_Index
				FROM group_list gl
					JOIN purchase_history_view phv ON phv.Customer_ID = gl.Customer_ID
					JOIN periods_view pv ON pv.Customer_ID = gl.Customer_ID AND pv.Group_ID = gl.Group_ID
				WHERE transaction_datetime BETWEEN pv.First_Group_Purchase_Date AND pv.Last_Group_Purchase_Date
				GROUP BY gl.Customer_ID, gl.Group_ID, pv.Group_Purchase
				),
				
Churn_Rate AS  -- расчет индекса оттока

/*Подсчет давности приобретения группы. Из даты формирования анализа вычитается
дата последней транзакции клиента, в которой была представлена
анализируемая группа. Для определения последней даты покупки группы
клиентом выбирается максимальное значение по полю Transaction_DateTime
таблицы История покупок для записей, в которых значения полей
Customer_ID и Group_ID соответствуют значениям аналогичных полей
таблицы Группы.


Расчет коэффициента оттока. Количество дней, прошедших после
даты последней транзакции клиента с анализируемой группой, 
делится на среднее количество дней между покупками
анализируемой группы клиентом (значение поля Group_Frequency
таблицы Периоды). Итоговое значение сохраняется в поле
Group_Churn_Rate таблицы Группы.
*/
			(
				
				SELECT ai.Customer_ID, ai.Group_ID, ai.Group_Affinity_Index, 
				EXTRACT(EPOCH FROM ((SELECT * FROM dateanalysisformation) - MAX(phv.Transaction_DateTime)))/pv.Group_Frequency / 86400.0 AS Group_Churn_Rate
				FROM Affinity_Index ai
				JOIN purchase_history_view phv ON phv.Customer_ID = ai.Customer_ID AND phv.Group_ID = ai.Group_ID
				JOIN periods_view pv ON pv.Customer_ID = ai.Customer_ID AND pv.Group_ID = ai.Group_ID
				GROUP BY ai.Customer_ID, ai.Group_ID, ai.Group_Affinity_Index, Group_Frequency
			),
			
			
-- Расчет стабильности потребления группы выполнялся в несколько шагов описанных ниже



/*
Stability_count_days
Расчет интервалов потребления группы. Определяются все интервалы
(в количестве дней) между транзакциями клиента, содержащими
анализируемую группу. Для этого все транзакции, содержащие
анализируемую группу в покупках клиента, ранжируются по дате
совершения (значению поля Transaction_DateTime таблицы История покупок) 
от самой ранней к самой поздней. Из даты каждой
последующей транзакции вычитается дата предыдущей. Каждый интервал
учитывается отдельно.
*/
Stability_count_days AS 
		(
			SELECT cr.Customer_ID, cr.Group_ID, cr.Group_Affinity_Index,cr.Group_Churn_Rate,
			EXTRACT(EPOCH FROM (Transaction_DateTime - LAG(Transaction_DateTime) 
														OVER (PARTITION BY 
															cr.Customer_ID,
															cr.Group_ID	
															ORDER BY 
															Transaction_DateTime ASC))) / 86400.0 AS tmp_res -- days_count
			
			FROM Churn_Rate cr
			JOIN purchase_history_view phv ON phv.Customer_ID = cr.Customer_ID AND phv.Group_ID = cr.Group_ID
			ORDER BY cr.Customer_ID, cr.Group_ID,Transaction_DateTime
		),

/*
Stability_absolute_deviation
Подсчет абсолютного отклонения каждого интервала от средней
частоты покупок группы. Из значения каждого интервала вычитается
среднее количество дней между транзакциями с анализируемой группой
(значение поля Group_Frequency таблицы Периоды). В случае,
если получившееся значение является отрицательным, оно умножается на
-1.
*/

Stability_absolute_deviation AS 
		(
			SELECT scd.Customer_ID, scd.Group_ID, scd.Group_Affinity_Index,scd.Group_Churn_Rate,
			ABS(scd.tmp_res - pv.Group_Frequency) AS  tmp_res -- absolute_deviation
			FROM Stability_count_days scd
			JOIN periods_view pv ON pv.Customer_ID = scd.Customer_ID AND pv.Group_ID = scd.Group_ID
			ORDER BY Customer_ID,Group_ID
		),
/*

Stability_relative_deviation
Подсчет относительного отклонения каждого интервала от средней
частоты покупок группы. Получившееся на предыдущем шаге значение для
каждого интервала делится на среднее количество дней между
транзакциями с анализируемой группой (значение поля
Group_Frequency таблицы Периоды).
*/

Stability_relative_deviation AS 
		(
			SELECT sad.Customer_ID, sad.Group_ID, sad.Group_Affinity_Index,sad.Group_Churn_Rate, sad.tmp_res / pv.Group_Frequency AS tmp_res
			FROM Stability_absolute_deviation sad
			JOIN periods_view pv ON pv.Customer_ID = sad.Customer_ID AND pv.Group_ID = sad.Group_ID
			ORDER BY Customer_ID, Group_ID
		),
/*
Group_Stability_Index
Определение стабильности потребления группы. Показатель
стабильности потребления группы определяется как среднее значение
всех показателей, получившихся на предыдущем шаге. Результат сохраняется в
поле Group_Stability_Index таблицы Группы.
*/		
Stability_Index AS 
		(
			SELECT srd.Customer_ID, srd.Group_ID, srd.Group_Affinity_Index,srd.Group_Churn_Rate, AVG(tmp_res) AS Group_Stability_Index
			FROM Stability_relative_deviation srd
			GROUP BY Customer_ID, Group_ID, Group_Affinity_Index, Group_Churn_Rate
			ORDER BY Customer_ID, Group_ID

		),
/* Далее для расчета маржи мне необходимо написать функцию, 
которая будет принимать в себя параметр для 
выбора варианта расчета маржи */

Margin AS (
	SELECT Customer_ID,Group_ID, Group_Affinity_Index, Group_Churn_Rate, Group_Stability_Index, fnc_calculation_margin(Customer_ID,Group_ID) AS Group_Margin
	FROM 
		Stability_Index 
	GROUP BY
		Customer_ID,
		Group_ID,
		Group_Affinity_Index,
		Group_Churn_Rate,
		Group_Stability_Index
	ORDER BY
		Customer_ID, 
		Group_ID
			),
	
/* 

Определение количества транзакций клиента со скидкой.
Определяется количество транзакций, в рамках которых анализируемая
группа была приобретена клиентом с применением какой-либо скидки.
Для подсчета используются уникальные значения по полю
Transaction_ID таблицы Чеки для транзакций, в рамках которых
клиент приобретал анализируемую группу, при этом значение поля
SKU_Discount таблицы Чеки больше нуля. Скидка,
представленная в рамках списания бонусных баллов, не учитывается.

*/
trans_with_discount AS   -- Определение количества транзакций клиента со скидкой.
	(
	SELECT margin.Customer_ID,margin.Group_ID,Group_Affinity_Index,Group_Churn_Rate,Group_Stability_Index,Group_Margin,
	COUNT(Checks.Transaction_ID) FILTER(WHERE SKU_Discount > 0) AS transactions_with_discount
	FROM margin
	JOIN Cards ON Cards.Customer_ID = margin.Customer_ID
	JOIN Transactions tr ON tr.Customer_Card_ID = Cards.Customer_Card_ID
	JOIN Checks ON Checks.Transaction_ID = tr.Transaction_ID
	JOIN ProductGrid pg ON pg.Group_ID = margin.Group_ID AND pg.SKU_ID = Checks.SKU_ID
	GROUP BY margin.Customer_ID, margin.Group_ID, Group_Affinity_Index, Group_Churn_Rate, Group_Stability_Index, Group_Margin
	ORDER BY Customer_ID, Group_ID
),

/*
Определение доли транзакций со скидкой. Количество транзакций, в
рамках которых приобретение товаров из анализируемой группы было
совершено со скидкой делится на общее
количество транзакций клиента с анализируемой группой за
анализируемый период (данные поля Group_Purchase таблицы Периоды для анализируемой группы по клиенту). Получившееся значения
сохраняется в качестве доли транзакций по покупке анализируемой
группы со скидкой в поле Group_Discount_Share таблицы Группы.
*/

share_of_transactions_with_discount AS   -- Определение доли транзакций со скидкой
(   
	SELECT twd.Customer_ID, twd.Group_ID, Group_Affinity_Index, Group_Churn_Rate, Group_Stability_Index, Group_Margin,
			transactions_with_discount * 1.0/ Group_Purchase AS Group_Discount_Share
	FROM trans_with_discount twd
	JOIN periods_view pv ON twd.Customer_ID = pv.Customer_ID  AND twd.Group_ID = pv.Group_ID
	GROUP BY twd.Customer_ID, twd.Group_ID, Group_Affinity_Index, Group_Churn_Rate, Group_Stability_Index, Group_Margin, Group_Discount_Share
	ORDER BY Customer_ID, Group_ID
),

/* 
Определение минимального размера скидки по группе. Определяется
минимальный размер скидки по каждой группе для каждого клиента. Для
этого выбирается минимальное не равное нулю значение поля
Group_Min_Discount таблицы Периоды для заданных клиента и
группы. Результат сохраняется в поле Group_Minimum_Discount
таблицы Группы.
*/
Min_Discount AS  -- Определение минимального размера скидки по группе
(
	SELECT shdis.Customer_ID, shdis.Group_ID, Group_Affinity_Index, Group_Churn_Rate, Group_Stability_Index, Group_Margin, Group_Discount_Share,
			MIN(Group_Min_Discount) FILTER (WHERE group_min_discount > 0) AS Group_Minimum_Discount
	FROM share_of_transactions_with_discount shdis
	JOIN periods_view pv ON shdis.Customer_ID = pv.Customer_ID  AND shdis.Group_ID = pv.Group_ID
	GROUP BY shdis.Customer_ID, shdis.Group_ID, Group_Affinity_Index, Group_Churn_Rate, Group_Stability_Index, Group_Margin, Group_Discount_Share
	ORDER BY Customer_ID, Group_ID
),

/*
Для определения
среднего размера скидки по группе для клиента фактически оплаченная
сумма по покупке группы в рамках всех транзакций (значение поля
Group_Summ_Paid таблицы История покупок для всех транзакций)
делится на сумму розничной стоимости данной группы в рамках всех
транзакций (сумма по группе по значению поля Group_Summ таблицы
История покупок). В расчете участвуют только транзакции, в которых была предоставлена скидка.
Результат сохраняется в поле Group_Average_Discount таблицы Группы.
*/

Avg_Discount AS -- Определение среднего размера скидки по группе.
(
	SELECT mindis.Customer_ID, mindis.Group_ID,Group_Affinity_Index ,Group_Churn_Rate,
		 Group_Stability_Index,
		fnc_calculation_margin(mindis.Customer_ID,mindis.Group_ID) AS Group_Margin,
		Group_Discount_Share, Group_Minimum_Discount, 
		SUM(Group_Summ_Paid)/SUM(Group_Summ) AS Group_Average_Discount
	FROM Min_Discount mindis
	JOIN purchase_history_view phv ON phv.Customer_ID = mindis.Customer_ID AND phv.Group_ID = mindis.Group_ID AND Group_Summ_Paid != Group_Summ
	GROUP BY mindis.Customer_ID, mindis.Group_ID, Group_Affinity_Index, Group_Churn_Rate,Group_Stability_Index,
		Group_Margin, Group_Discount_Share, Group_Minimum_Discount
	ORDER BY Customer_ID, Group_ID
) 

SELECT * FROM Avg_Discount;



/* 
Выбор метода расчета маржи. По умолчанию маржа рассчитывается
для всех транзакций в рамках анализируемого периода (используются
все доступные данные). Но пользователь должен иметь возможность
внести индивидуальные настройки и выбрать метод расчета актуальной
маржи – по периоду или по количеству транзакций.


В случае выбора метода расчета маржи по периоду пользователь
указывает, за какое количество дней от даты формирования анализа в обратном
хронологическом порядке необходимо рассчитать маржу. Для
расчета берутся все транзакции, в которых присутствует
анализируемая группа, совершенные пользователем в указанный
период. Для подсчетов используются данные, содержащиеся в поле
Transaction_DateTime таблицы История покупок.


В случае выбора метода расчета маржи по количеству транзакций
пользователь указывает количество транзакций, для которых
необходимо рассчитать маржу. Маржа считается по заданному
количеству транзакций, начиная с последней, в обратном
хронологическом порядке. Для подсчетов используются данные,
содержащиеся в поле Transaction_DateTime таблицы История
покупок`.

*/

CREATE OR REPLACE FUNCTION fnc_calculation_margin(
    Cust_ID bigint,
    Gr_ID bigint,
    type_calculation integer DEFAULT 1,
    param_amount integer DEFAULT NULL
) RETURNS NUMERIC AS
$BODY$
DECLARE
    limit_date TIMESTAMP;
BEGIN
    IF type_calculation = 1 THEN
		IF param_amount IS NULL THEN
			param_amount := 1000000;
		END IF;
	limit_date := (SELECT * FROM dateanalysisformation) - param_amount * INTERVAL '1 day';
	RETURN
		(
			SELECT SUM(Group_Summ_Paid - Group_Cost)::NUMERIC AS Group_Margin
			FROM purchase_history_view phv
			WHERE phv.Customer_ID = Cust_ID AND phv.Group_ID = Gr_ID AND Transaction_DateTime > limit_date
			GROUP BY Customer_ID, Group_ID
		);
	ELSEIF type_calculation = 2 THEN
		IF param_amount IS NULL THEN
			param_amount := (SELECT COUNT(Transaction_ID)FROM purchase_history_view);
		END IF;
	RETURN 
		(
			SELECT SUM(Group_Summ_Paid - Group_Cost)::NUMERIC AS Group_Margin
			FROM 
				(
					SELECT * FROM purchase_history_view phv
					WHERE phv.Customer_ID = Cust_ID AND phv.Group_ID = Gr_ID
					ORDER BY Transaction_DateTime DESC
					LIMIT param_amount
				) AS tmp
			
		);
	END IF;
END;
$BODY$ 
LANGUAGE plpgsql;

	
-- SELECT * FROM Groups_View;
-- SELECT * FROM purchase_history_view;
