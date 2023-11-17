/*##########################################################################################################################################################################################################################################

Поле									Название поля в системе			Формат / возможные значения			Описание
Идентификатор клиента					Customer_ID						---									---
Идентификатор группы SKU				Group_ID						---									Идентификатор группы родственных товаров, к которой относится товар. Указывается один идентификатор для всех товаров в группе
Дата первой покупки группы				First_Group_Purchase_Date		гггг-мм-ддTчч:мм:сс.0000000			---
Дата последней покупки группы			Last_Group_Purchase_Date		гггг-мм-ддTчч:мм:сс.0000000			---
Количество транзакций с группой			Group_Purchase					Арабская цифра, десятичная дробь	---
Интенсивность покупок группы			Group_Frequency					Арабская цифра, десятичная дробь	---
Минимальный размер скидки по группе		Group_Min_Discount				Арабская цифра, десятичная дробь	---

#############################################################################################################################################################################################################################################
*/


/*
1) Определение даты первой покупки группы клиентом. Дата первой
покупки группы клиентом определяется на основе данных, содержащихся
в поле Transaction_DateTime таблицы История покупок. Из всей
совокупности записей, в рамках которых идентификаторы клиента и
группы равны идентификаторам клиента и группы анализируемой строки
таблицы Периоды, выбирается минимальное значение по полю
Transaction_DateTime таблицы История покупок. Результат
сохраняется в поле First_Group_Purchase_Date таблицы Периоды.


2) Определение даты последней покупки группы клиентом. Дата
последней покупки группы клиентом определяется на основе данных,
содержащихся в поле Transaction_DateTime таблицы История
покупок. Из всей совокупности записей, в рамках которых
идентификаторы клиента и группы равны идентификаторам клиента и
группы анализируемой строки таблицы Периоды, выбирается
максимальное значение по полю Transaction_DateTime таблицы История
покупок. Результат сохраняется в поле
Last_Group_Purchase_Date таблицы Периоды.


3) Определение количества транзакций с анализируемой группой.
Определяется количество транзакций клиента в рамках анализируемого
периода, в которых присутствует анализируемая группа. Для этого
используются данные, содержащиеся в полях Customer_ID,
Transaction_ID (берутся уникальные значения по полю
Transaction_ID) и Group_ID (берется идентификатор анализируемой
группы) таблицы История покупок. Значения в полях
Customer_ID и Group_ID в таблице История покупок должны
соответствовать значениям в аналогичных полях таблицы Периоды.
Результат сохраняется в поле Group_Purchase таблицы Периоды.


4) Определение интенсивности покупок группы. Для определения
интенсивности покупок группы из даты последней транзакции с группой
(значение поля Last_Group_Purchase_Date таблицы Периоды)
вычитается значение поля (значение поля First_Group_Purchase_Date
таблицы Периоды), добавляется единица, после чего результат
делится на количество транзакций с анализируемой группой (значение
поля Group_Purchase таблицы Периоды). Результат сохраняется
в поле Group_Frequency таблицы Периоды.


5) Подсчет минимальной скидки по группе. Для каждой группы каждой
транзакции устанавливается минимальный размер скидки, который был
предоставлен в рамках данной транзакции. Для этого предоставленный
размер скидки по каждому SKU (значение поля SKU_Discount таблицы
Чеки) делится на базовую розничную стоимость данного SKU
(значение поля SKU_Summ таблицы Чеки). Результат сохраняется
в поле Group_Min_Discount таблицы Периоды. В случае
отсутствия скидки по всем SKU группы указывается значение 0.

*/


-- SELECT * FROM purchase_history_view;


CREATE OR REPLACE VIEW periods_view AS
WITH cte AS (
					
					SELECT Customer_ID, Group_ID ,MIN(transaction_datetime) AS First_Group_Purchase_Date,  
												  MAX(transaction_datetime) AS Last_Group_Purchase_Date, 
												  COUNT(transaction_id) AS Group_Purchase,
												((EXTRACT(EPOCH FROM(MAX(transaction_datetime) - MIN(transaction_datetime))) / 86400.0 + 1)/ (COUNT(transaction_id)) ) AS Group_Frequency
					FROM purchase_history_view
					GROUP BY Customer_ID, Group_ID
					),
discount AS (
			
				SELECT pers.customer_id,group_id, sku_discount::FLOAT / sku_summ AS group_discount
				FROM personalinformation pers
					JOIN cards ON cards.Customer_ID = pers.Customer_ID
					JOIN transactions tr ON tr.Customer_Card_ID = cards.Customer_Card_ID
					JOIN checks ON checks.Transaction_ID = tr.Transaction_ID
					JOIN productgrid pg ON pg.SKU_ID = checks.SKU_ID
				GROUP BY pers.customer_id,group_id,group_discount
				ORDER BY customer_id,group_id

)
 SELECT cte.Customer_ID,cte.Group_ID, First_Group_Purchase_Date, Last_Group_Purchase_Date, Group_Purchase, Group_Frequency,
				 	CASE
						WHEN MAX(group_discount) = 0 THEN 0
						ELSE (MIN(group_discount) FILTER ( WHERE group_discount > 0 ))
					END AS Group_Min_Discount
				FROM cte
					JOIN discount gd ON gd.Customer_ID = cte.Customer_ID AND gd.Group_ID = cte.Group_ID
				GROUP BY cte.Customer_ID,cte.Group_ID, First_Group_Purchase_Date, Last_Group_Purchase_Date, Group_Purchase, Group_Frequency;



-- TEST --

-- SELECT * FROM periods_view
-- WHERE group_id = 1

-- SELECT * FROM periods_view
-- WHERE last_group_purchase_date = '2020-09-14 22:39:05'


-- SELECT * FROM periods_view
-- WHERE group_purchase > 9
