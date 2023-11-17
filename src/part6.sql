-- SELECT * FROM groups_view
-- SELECT * FROM customers_view
-- SELECT * FROM productgrid


CREATE OR REPLACE FUNCTION fnc_cross_sell ( 
    amount_of_groups BIGINT,  -- количество групп
    max_churn_index NUMERIC,  -- максимальный индекс оттока
    max_consumption_stability_index NUMERIC,  -- максимальный индекс стабильности потребления
    max_SKU_share NUMERIC,  -- максимальная доля SKU (в процентах)
    allowable_margin_share INTEGER  -- допустимая доля маржи (в процентах)
) 
RETURNS TABLE ( Customer_ID INTEGER, SKU_Name VARCHAR(255), Offer_Discount_Depth FLOAT )
AS
$BODY$
BEGIN 
RETURN QUERY
	SELECT tmp_customer_id::INTEGER, tmp_sku_name, CEIL(tmp_group_minimum_discount * 100 / 5) * 5
		FROM (
                SELECT *, ROW_NUMBER() OVER( PARTITION BY tmp_customer_id ORDER BY tmp_group_affinity_index ) AS tmp_group_cnt,  -- подсчитываем количесвто самых востребованных груп для каждого клиента
                    MAX(tmp_margin) OVER(PARTITION BY tmp_customer_id) AS tmp_max_margin,  -- Запоминаем максимальную маржу SKU для каждого клиента
                    allowable_margin_share * tmp_margin / tmp_sku_retail_price AS tmp_calculated_discount -- расчет скидки для клиента
			FROM
				(
				  SELECT  DISTINCT gv.customer_id AS tmp_customer_id,
                            gv.group_id AS tmp_group_id,
                            gv.group_affinity_index AS tmp_group_affinity_index,
					        gv.group_churn_rate AS tmp_group_churn_rate,
                            stores.sku_retail_price - stores.sku_purchase_price AS tmp_margin,  -- Маржи SKU(товаров) для поиска максимальной
                            stores.sku_retail_price AS tmp_sku_retail_price,
                            productgrid.sku_name AS tmp_sku_name,  -- Имя SKU(товара)
                            100.0 * COUNT(productgrid.sku_name) OVER () / COUNT(gv.group_id) OVER () AS tmp_sku_share,  -- Доля SKU(товара) в своей группе
                            gv.group_minimum_discount AS tmp_group_minimum_discount,  -- Запоминаем минимальную скидку для рассчета итоговой скидки
                            customers_view.customer_primary_store AS tmp_customer_primary_store,  -- Запоминаем основной магазин каждого клиента для внешнего запроса
                            stores.transaction_store_id AS tmp_transaction_store_id
                        FROM
                            groups_view gv
                            JOIN productgrid ON productgrid.group_id = gv.group_id
                            JOIN stores ON stores.sku_id = productgrid.sku_id
                            JOIN transactions ON transactions.transaction_store_id = stores.transaction_store_id
                            JOIN customers_view ON customers_view.customer_id = gv.customer_id
                        WHERE
                            gv.group_churn_rate <= max_churn_index  -- Индекс оттока по группе не более заданного пользователем значения.
                            AND gv.group_stability_index <  max_consumption_stability_index  -- Индекс стабильности потребления группы составляет менее заданного пользователем значения.
				) AS tmp_1	
		) AS tmp_2
	WHERE tmp_group_cnt <= amount_of_groups -- филтруем по количеству групп, которое ввел пользователь
	AND tmp_max_margin = tmp_margin  -- выбираем продукты с максимальной маржой
	AND tmp_sku_share <= max_SKU_share -- фильтруем по максимальной доле продукта, которую вввел ползователь
	AND tmp_customer_primary_store = tmp_transaction_store_id -- рассматриваем результаты только по основному магазину клиента 
	AND CEIL(tmp_group_minimum_discount * 100 / 5) * 5 <= tmp_calculated_discount; -- округляем вверх с шагом 5%

END;
$BODY$
LANGUAGE plpgsql;


-- TEST
-- SELECT * FROM fnc_cross_sell( 5, 3, 0.5, 100, 30);
