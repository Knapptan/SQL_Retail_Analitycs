


---------------------------------------------------------------------------------------------------------------


DROP FUNCTION IF EXISTS fnc_avg_check_in_period CASCADE;
DROP FUNCTION IF EXISTS fnc_avg_check_amount_trans CASCADE;
DROP FUNCTION IF EXISTS fnc_find_group CASCADE;
DROP FUNCTION IF EXISTS fnc_create_personal_offer CASCADE;



CREATE OR REPLACE FUNCTION fnc_avg_check_in_period(date_begin DATE DEFAULT '2015-01-31', date_end DATE DEFAULT '2023-11-13')
RETURNS TABLE ( Customer_ID INTEGER, Average_check NUMERIC )
AS
$BODY$
BEGIN
    RETURN QUERY
        (SELECT pi.customer_id, AVG(tr.transaction_summ)
         FROM cards c
         JOIN personalinformation pi ON pi.customer_id = c.customer_id
         JOIN transactions tr ON tr.customer_card_id = c.customer_card_id
         WHERE tr.transaction_datetime BETWEEN date_begin AND date_end
         GROUP BY pi.customer_id);
END;
$BODY$ 
LANGUAGE plpgsql;



/*
Пользователь выбирает методику расчета по количеству последних
транзакций, после чего вручную указывает количество
транзакций, по которым необходимо рассчитать средний чек. Для
расчета среднего чека берется заданное пользователем
количество транзакций, начиная с самой последней в обратном
хронологическом порядке. В случае, если каким-либо клиентом из
выборки за весь анализируемый период совершено меньше
указанного количества транзакций, для анализа используется
имеющееся количество транзакций.
*/

CREATE OR REPLACE FUNCTION fnc_avg_check_amount_trans(amount_transactions INT)
RETURNS TABLE( Customer_ID INTEGER, Average_check NUMERIC )
AS
$BODY$
BEGIN
    RETURN QUERY
        (
			WITH latest_transaction AS (SELECT pi.customer_id, (SUM(alltrans.transaction_summ) / COUNT(alltrans.row_numb)) AS sum, row_numb
                          FROM personalinformation pi
                          JOIN (SELECT p.customer_id,
										ROW_NUMBER()OVER (PARTITION BY p.customer_id ORDER BY t2.transaction_datetime DESC) AS row_numb,
                                	    t2.transaction_summ
                                FROM personalinformation p
                                JOIN cards c2 ON p.customer_id = c2.customer_id
                                JOIN transactions t2 ON c2.customer_card_id = t2.customer_card_id
                                GROUP BY p.customer_id, t2.transaction_datetime, t2.transaction_summ) alltrans ON alltrans.customer_id = pi.customer_id
                          WHERE alltrans.row_numb <= amount_transactions
                          GROUP BY pi.customer_id, row_numb)

         SELECT latest_transaction.customer_id, SUM(sum) / COUNT(row_numb)
         FROM latest_transaction
         GROUP BY latest_transaction.customer_id
		);
END;
$BODY$
LANGUAGE plpgsql;

-- SELECT * FROM fnc_avg_check_amount_trans (10)


CREATE OR REPLACE FUNCTION fnc_find_group(in_max_churn_index NUMERIC, -- максимальный индекс оттока
										  in_max_share_of_transactions NUMERIC,  -- максимальная доля транзакций со скидкой (в процентах)
                                          in_margin_share NUMERIC) -- допустимая доля маржи (в процентах)
										  
RETURNS TABLE ( Customer_ID INTEGER, Group_name VARCHAR, Discount_depth FLOAT )
AS
$BODY$
BEGIN
    RETURN QUERY
        WITH cte AS (SELECT DISTINCT p.customer_id,
                                     pg.group_id,
                                     sg.group_name,
                                     groups.group_affinity_index,
                                     (CEIL((group_minimum_discount * 100) / 5) * 5) AS discount
					 FROM personalinformation p
					 	JOIN cards ON cards.customer_id = p.customer_id
					 	JOIN transactions tr ON tr.customer_card_id = cards.customer_card_id
					 	JOIN checks ch ON ch.transaction_id = tr.transaction_id
					    JOIN productgrid pg ON pg.sku_id = ch.sku_id
   					    JOIN stores s ON s.sku_id = pg.sku_id
                        JOIN sku_groups sg on sg.group_id = pg.group_id
                        JOIN groups_view groups ON p.customer_id = groups.customer_id AND pg.group_id = groups.group_id
                     WHERE groups.group_minimum_discount > 0 AND groups.group_churn_rate < in_max_churn_index
                       AND groups.group_discount_share < (in_max_share_of_transactions::numeric / 100.0)
                       AND CEIL((group_minimum_discount * 100) / 5) * 5 <
                           ((sku_retail_price - s.sku_purchase_price) * in_margin_share /
                            s.sku_retail_price))
        SELECT cte.customer_id, cte.group_name, cte.discount
        FROM cte
        WHERE (cte.customer_id, cte.group_affinity_index) IN
              (SELECT cte.customer_id, MAX(cte.group_affinity_index) FROM cte GROUP BY cte.customer_id)
        ORDER BY Customer_ID;
END;
$BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fnc_create_personal_offer (type_calculation INTEGER, -- метод расчета среднего чека 
                                               date_begin DATE, -- первая дата периода (для 1 метода)
                                               date_end DATE, -- последняя дата периода (для 1 метода)
                                               amount_transactions INTEGER, -- количество транзакций (для 2 метода)
                                               coef_avg_check NUMERIC, -- коэффициент увеличения среднего чека
                                               max_churn_index NUMERIC, -- максимальный индекс оттока
                                               max_share_discount_transactions NUMERIC, -- максимальная доля транзакций со скидкой (в процентах)
                                               allowable_margin_share NUMERIC) -- допустимая доля маржи (в процентах)

RETURNS TABLE
            ( Customer_ID INTEGER, Required_Check_Measure NUMERIC, Group_Name VARCHAR,Offer_Discount_Depth FLOAT )
AS
$BODY$
DECLARE
    check_date_begin DATE := (SELECT MAX(transaction_datetime) FROM transactions);
    check_last_date  DATE := (SELECT MIN(transaction_datetime) FROM transactions);
BEGIN

/*
Пользователь выбирает методику расчета по периоду, после чего
указывает первую и последнюю даты периода, за который
необходимо рассчитать средний чек для всей совокупности
клиентов, попавших в выборку. При этом последняя дата
указываемого периода должна быть позже первой, а указанный
период должен быть внутри общего анализируемого периода. В
случае указания слишком ранней или слишком поздней даты
система автоматически подставляет дату, соответственно, начала
или окончания анализируемого периода. Для расчета учитываются
все транзакции, совершенные каждым конкретным клиентом в
течение заданного периода.
*/

    IF (type_calculation = 1) THEN
        IF date_begin > date_end THEN
            RAISE EXCEPTION 'ОШИБКА! Первая дата должна быть раньше последней! Проверьте дату начала:(%) и дату конца:(%) ', date_begin, date_end;
        ELSEIF date_begin > check_date_begin THEN
            date_begin := check_date_begin;
        ELSEIF
            date_end < check_last_date THEN
            date_end := check_last_date;
        END IF;
        RETURN QUERY (SELECT pi.customer_id,
                             avgcheckinper.Average_check * coef_avg_check,
                             findgroup.Group_name,
                             findgroup.Discount_depth
                      FROM personalinformation pi
                               JOIN fnc_avg_check_in_period(date_begin, date_end) avgcheckinper ON pi.customer_id = avgcheckinper.Customer_ID
                               JOIN fnc_find_group(max_churn_index, max_share_discount_transactions, allowable_margin_share) findgroup
                                    ON pi.customer_id = findgroup.Customer_ID);

    ELSEIF (type_calculation = 2) THEN
        RETURN QUERY (SELECT pi.customer_id,
                             avgcheckintrans.Average_check * coef_avg_check,
                             findgroup.Group_name,
                             findgroup.Discount_depth
                      FROM personalinformation pi
                               JOIN
                           fnc_avg_check_amount_trans(amount_transactions) avgcheckintrans
                           ON pi.customer_id = avgcheckintrans.Customer_ID
                               JOIN fnc_find_group(max_churn_index, max_share_discount_transactions,
                                                     allowable_margin_share) findgroup
                                    ON pi.customer_id = findgroup.Customer_ID);
    END IF;
END;
$BODY$ 
LANGUAGE plpgsql;



-- TEST

-- SELECT * FROM fnc_create_personal_offer (1, '2018-08-23', '2019-09-22', NULL, 1.15, 3, 70, 60);

-- SELECT * FROM fnc_create_personal_offer (2, NULL, NULL, 10, 1.15, 3, 70, 30);