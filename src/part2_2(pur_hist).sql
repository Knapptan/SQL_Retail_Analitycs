-- Определение транзакций клиента. Для каждого клиента формируется
-- список уникальных транзакций по всем его картам. Для этого
-- используются данные, содержащиеся в поле Transaction_ID таблицы
-- Транзакции. Связка с идентификатором клиента (Customer_ID
-- таблицы Персональные данные) осуществляется через
-- идентификаторы всех карт клиента (поле Customer_Card_ID таблиц
-- Карты и Транзакции). Результат сохраняется
-- в поле Transaction_ID таблицы История покупок. В таблице
-- сохраняются уникальные значения Идентификатор клиента
-- (Customer_ID) – Идентификатор транзакции (Transaction_ID).


-- Определение дат совершения транзакций. Для каждой транзакции
-- указывается ее дата. Для определения даты совершения транзакции
-- используются данные, содержащиеся в поле Transaction_DateTime таблицы
-- Транзакции, идентификация осуществляется по полю
-- Transaction_ID таблиц История покупок и Транзакции.
-- Результат сохраняется в поле Transaction_DateTime таблицы История покупок.


-- Определение списка SKU. Для каждой транзакции указывается список
-- SKU, которые были приобретены клиентом в рамках конкретной
-- транзакции. Для этого используются данные, содержащиеся в поле
-- SKU_ID таблицы Чеки. Сопоставление осуществляется на
-- основании данных, содержащихся в полях Transaction_ID таблиц История покупок и Чеки.


-- Дедубликация списка SKU. Список SKU дедублицируется
-- индивидуально для каждой транзакции. Для каждой транзакции
-- формируется список уникальных SKU.


-- Определение списка групп. Для каждого SKU на основании данных из
-- товарной матрицы указывается его группа. Для этого используются
-- данные, содержащиеся в поле Group_ID таблицы Товарная
-- матрица, сопоставление осуществляется по полю SKU_ID таблиц История покупок и Товарная матрица.


-- Дедубликация списка групп. Список групп дедублицируется
-- индивидуально для каждой транзакции. Итоговый результат сохраняется
-- в поле Group_ID таблицы История покупок. В таблице должны
-- содержаться уникальные значения, сформированные из совокупности
-- данных Идентификатор клиента (Customer_ID) – Идентификатор
-- транзакции (Transaction_ID) – Идентификатор группы (Group_ID).
-- При этом дата транзакции автоматически распространяется на все
-- группы, которые были приобретены в рамках данной транзакции.


-- Подсчет финансовых показателей по группе. Для каждого клиента по
-- каждой группе осуществляется подсчет основных финансовых показателей
-- путем суммирования аналогичных показателей для всех SKU, входящих в
-- конкретную группу. Суммируются данные из таблицы Чеки.
-- Подсчитываются следующие показатели:


-- Себестоимость купленного клиентом товара в течение
-- анализируемого периода. Суммируются значения, полученные путем умножения данных из поля SKU_Purchase_Price на данные из поля SKU_Amount
-- по всем SKU анализируемой группы для клиента. Данные
-- сохраняются в поле Group_Cost таблицы История покупок.


-- Базовая розничная стоимость в течение анализируемого периода.
-- Суммируются данные из поля SKU_Summ по всем SKU
-- анализируемой группы для клиента. Данные сохраняются в поле
-- Group_Summ таблицы История покупок.


-- Фактически оплаченная стоимость (с учетом оплаты покупок
-- бонусами программы лояльности, но без учета скидок).
-- Суммируются данные их поля SKU_Summ_Paid по всем SKU
-- анализируемой группы для клиента. Данные сохраняются в поле
-- Group_Summ_Paid таблицы История покупок.


CREATE OR REPLACE VIEW purchase_history_view AS 
WITH Uniq_Transactions AS (
SELECT personalinformation.customer_id,
       transactions.transaction_id,
	   transactions.transaction_datetime,
	   transactions.transaction_store_id,
	   checks.sku_id,
	   productgrid.group_id,
	   stores.sku_purchase_price,
	   checks.sku_amount,
	   checks.sku_summ,
	   checks.sku_summ_paid
	   
FROM personalinformation
JOIN cards ON cards.customer_id = personalinformation.customer_id
JOIN transactions ON cards.customer_card_id = transactions.customer_card_id
JOIN checks ON 	transactions.transaction_id = checks.transaction_id
JOIN productgrid ON productgrid.sku_id = checks.sku_id
JOIN stores ON stores.sku_id = checks.sku_id
	              AND stores.transaction_store_id = transactions.transaction_store_id
)

SELECT customer_id,
       transaction_id,
	   transaction_datetime,
	   group_id,
	   SUM (sku_purchase_price * SKU_Amount)  AS Group_Cost,
	   SUM(sku_summ) AS Group_Summ,
       SUM(sku_summ_paid) AS Group_Summ_Paid	   
FROM Uniq_Transactions
GROUP BY 
       customer_id,
       transaction_id,
	   transaction_datetime,
	   group_id;


-- TEST -- 

-- SELECT * FROM purchase_history_view
-- WHERE group_id = 5

-- SELECT transaction_id,customer_name, transaction_datetime, group_cost, Group_Summ, Group_Summ_Paid
-- FROM purchase_history_view phw
-- JOIN personalinformation pi ON pi.customer_id = phw.customer_id
-- WHERE group_cost > 2000