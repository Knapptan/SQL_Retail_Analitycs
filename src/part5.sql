--Основная логика:
-- Определение текущей частоты посещений: Для каждого клиента рассчитывается средняя частота визитов
-- на основе разницы между конечной и начальной датами заданного периода и средней интенсивностью транзакций клиента.
-- Определение транзакции для начисления вознаграждения:
-- Система определяет, на какой транзакции в рамках заданного периода следует начислить вознаграждение клиенту. Для этого к текущему количеству транзакций добавляется число транзакций, заданное пользователем.
-- Определение группы для формирования вознаграждения: 
-- Выбирается группа товаров, которая соответствует ряду критериев, включая индекс востребованности, индекс оттока и долю транзакций со скидкой.
-- Определение максимально допустимого размера скидки: 
-- На этом этапе рассчитывается максимальная глубина скидки на основе средней маржи клиента по выбранной группе товаров и заданной доли маржи.
-- Определение величины скидки: 
-- Затем, система определяет окончательную глубину скидки для каждой группы товаров, сравнивая рассчитанное значение со значением минимальной скидки для клиента по этой группе.

-- Для того чтобы Postgres воспринимал дату в превычном в РФ формате
SET datestyle = 'ISO, DMY';


-- Удаляем возможноую одноименную функцию
DROP FUNCTION IF EXISTS fnc_formation_offers_growth_visits(TIMESTAMP, TIMESTAMP, INT, FLOAT , FLOAT, FLOAT);
-- Создаем функцию, определяющую предложения, ориентированные на рост частоты визитов
CREATE OR REPLACE FUNCTION fnc_formation_offers_growth_visits(
-- Входные данные
    date_start TIMESTAMP, -- дата начала периода
    date_end TIMESTAMP, -- дата окончания периода
    added_transactions INT, -- добавляемое число транзакций
    max_churn_index FLOAT, -- максимальный индекс оттока
    max_discount_ratio FLOAT, -- максимальная доля транзакций со скидкой (в процентах)
    max_margin_ratio FLOAT -- допустимая доля маржи (в процентах)
)
-- Выходные данные
RETURNS TABLE (
    customer_id INT, -- идентификатор клиента
    start_date TIMESTAMP, -- дата начала периода
    end_date TIMESTAMP, -- дата окончания периода
    required_transactions_count INT, -- порядковый номер транзакции, на которую начисляется вознаграждение
    group_name VARCHAR, -- название группы предложения
    offer_discount_depth INT -- максимально возможный размер скидки 
)
AS $$
BEGIN
    RETURN QUERY
----------------------------- Предварительные запросы -----------------------------
    WITH 
    target_transactions AS (
        SELECT 
            -- Определение текущей частоты посещений клиента в заданный период.
            ROUND(EXTRACT(DAY FROM (date_end - date_start)) / cv.customer_frequency)
            -- Определение транзакции для начисления вознаграждения.
            :: INT + added_transactions AS target,
			cv.customer_id AS transactions_customer_id  -- айди клиента для удобства группировки 
        FROM customers_view cv
    ),
-- SELECT * FROM customers_view
    maximum_allowable_discount AS (
        SELECT
/* Итоговое значение максимально допустимой скидки рассчитывается 
путем умножения заданного значения на среднюю маржу клиента по группе. */
            (AVG(phv.group_summ) - AVG(phv.group_cost)) / 100.0 * max_margin_ratio 
            / AVG(phv.group_cost) AS pre_offer_discount_depth,-- максимально допустимая скидка
            phv.customer_id AS purchase_customer_id, -- айди клиента для удобства группировки 
            phv.group_id -- айди группы для удобства группировки 
        FROM
            purchase_history_view phv  
        GROUP BY
            phv.customer_id,
            phv.group_id
    )
-- SELECT * FROM purchase_history_view 

-------------------------------------------- Итоговый запрос --------------------------------------------

    SELECT 
        DISTINCT ON (gv.customer_id) gv.customer_id::INT,
        date_start as Start_date,
        date_end as End_date,
        tt.target AS target_transactions_count,
        sku_groups.group_name AS group_name,
		/* В случае,
               если минимальная скидка после округления меньше значения,
               получившегося на шаге 5, она устанавливается в качестве скидки для
               группы в рамках предложения для клиента. */
        (CEIL(group_minimum_discount / 0.05) * 0.05 * 100)::INT AS offer_discount_depth
    FROM groups_view gv
-- SELECT * FROM groups_view
    JOIN sku_groups ON sku_groups.group_id = gv.group_id
    JOIN periods_view pv ON pv.customer_id = gv.customer_id AND pv.group_id = gv.group_id 
    JOIN customers_view cv ON cv.customer_id = gv.customer_id
    JOIN target_transactions tt ON tt.transactions_customer_id = gv.customer_id
    JOIN maximum_allowable_discount mad ON mad.purchase_customer_id = gv.customer_id
        AND mad.group_id = gv.group_id
    WHERE
	-- Индекс оттока по данной группе не должен превышать заданного пользователем значения.
        group_churn_rate <= max_churn_index
	-- Доля транзакций со скидкой по данной группе – менее заданного пользователем значения. 
        AND group_discount_share < max_discount_ratio / 100
		/* Определение величины скидки. Значение, полученное на шаге 5,
               сравнивается с минимальной скидкой, которая была зафиксирована для
               клиента по данной группе, округленной вверх с шагом в 5%. */
        AND CEIL(group_minimum_discount / 0.05) * 0.05 < pre_offer_discount_depth
    ORDER BY
        gv.customer_id,
		-- Индекс востребованности группы – максимальный из всех возможных.
        gv.group_affinity_index DESC, 
        gv.group_id;
		
-- SELECT * FROM groups_view
		
END;
$$ LANGUAGE plpgsql;


SELECT * FROM fnc_formation_offers_growth_visits (
    '01.06.2022 00:00:00', 
    '31.08.2022 00:00:00',
    1,
    4,
    80,
    50
);
