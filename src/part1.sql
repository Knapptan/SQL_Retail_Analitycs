DROP TABLE IF EXISTS PersonalInformation;
CREATE TABLE PersonalInformation (
	Customer_ID SERIAL PRIMARY KEY,
    Customer_Name VARCHAR(111) 
    CHECK (Customer_Name ~* '^([А-ЯA-Z][а-яa-z\- ]+)$'),
    Customer_Surname VARCHAR(111) 
    CHECK (Customer_Surname ~* '^([А-ЯA-Z][а-яa-z\- ]+)$'),
    Customer_Primary_Email VARCHAR(111) UNIQUE 
    CHECK (Customer_Primary_Email ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$'),
    Customer_Primary_Phone VARCHAR(15) UNIQUE 
    CHECK (Customer_Primary_Phone ~ '^\+7[0-9]{10}$')
);

DROP TABLE IF EXISTS Cards;
CREATE TABLE Cards(
	Customer_Card_ID SERIAL PRIMARY KEY,
	Customer_ID BIGINT,
	CONSTRAINT fk_cards_personal_information_customer_ID FOREIGN KEY (Customer_ID) REFERENCES PersonalInformation(Customer_ID)
);



-- ################################################################################################################
-- Таблица Транзакции(Transactions)					 															  #
--																												  #
--        Поле                        Название поля в системе                  Описание 						  #
--																												  #
--  Идентификатор транзакции               Transaction_ID                 Уникальное значение					  #
--  Идентификатор карты                    Customer_Card_ID     												  #
--  Сумма транзакции					   Transaction_Summ    Сумма транзакции в рублях(сумма покупки без скидок)#
--	Дата транзакции						   Transaction_DateTime			Дата и время совершения транзакции		  #
--  Торговая точка                         Transaction_Store_ID      Магазин, в котором была совершена транзакция #
-- ################################################################################################################
DROP TABLE IF EXISTS Transactions;
CREATE TABLE Transactions(
	Transaction_ID SERIAL PRIMARY KEY,
	Customer_Card_ID BIGINT,
	Transaction_Summ NUMERIC CHECK (Transaction_Summ >= 0),
	Transaction_DateTime TIMESTAMP,
	Transaction_Store_ID INT,
	CONSTRAINT fk_customer_card_id FOREIGN KEY (Customer_Card_ID) REFERENCES Cards(Customer_Card_ID)
);



-- ################################################################################################################
-- Таблица Товарная матрица(ProductGrid)																		  #
--																												  #
--        Поле                        Название поля в системе                  Описание 						  #
--																												  #
--  Идентификатор товара                    SKU_ID                     											  #
--  Название товара                         SKU_Name           													  #
--  Группа SKU                              Group_ID        	Идентификатор группы родственных товаров,		  #
--																		к которой относится товар 				  #
-- ################################################################################################################
DROP TABLE IF EXISTS ProductGrid;
CREATE TABLE ProductGrid(
	SKU_ID SERIAL PRIMARY KEY,
	SKU_Name VARCHAR(255)
	CHECK (SKU_Name ~ '^[A-Za-zА-Яа-я0-9\s\-\+\=\@\#\$\%\^\&\*\(\)\[\]\{\}\;\:\,\.\<\>\?\/\|\_\~]+$'),
	Group_ID BIGINT
);




-- #################################################################################################################
-- Таблица Чеки(Checks)		*БС - без учеьа скидки			 										 			   #
--																												   #
--        Поле                        Название поля в системе                  Описание 						   #
--																												   #
--  Идентификатор транзакции               Transaction_ID                Указывается для всех позиций в чеке	   #
--  Позиция в чеке                         SKU_ID  																   #
--  Количество штук или килограмм		   SKU_Amount              Указание, какое количество товара было куплено  #
--	Сумма, на которую был куплен товар	   SKU_Summ			    Сумма покупки фактического объема данного товара БС#
--  Оплаченная стоимость покупки товара    SKU_Summ_Paid      Фактически оплаченная сумма покупки данного товара БС#
-- Предоставленная скидка                  SKU_Discount           Размер предоставленной на товар скидки в рублях  #
-- #################################################################################################################
DROP TABLE IF EXISTS Checks;
CREATE TABLE Checks(
	Transaction_ID BIGINT,
	SKU_ID BIGINT NOT NULL,
	SKU_Amount NUMERIC
	CHECK (SKU_Amount > 0),
	SKU_Summ NUMERIC
	CHECK (SKU_Summ >= 0),
	SKU_Summ_Paid NUMERIC,
	CHECK (SKU_Summ_Paid >= 0),
	SKU_Discount NUMERIC
	CHECK(SKU_Discount >= 0),
	CONSTRAINT fk_transaction_id_transaction FOREIGN KEY (Transaction_ID) REFERENCES Transactions(Transaction_ID),
	CONSTRAINT fk_sku_id FOREIGN KEY (SKU_ID) REFERENCES ProductGrid(SKU_ID)
);





-- ################################################################################################################
-- Таблица Торговые точки(Stores)		        																  #
--																												  #
--        Поле                        Название поля в системе                   Описание 	   					  #
--																												  #
--  Торговая точка                     Transaction_Store_ID            											  #
--  Идентификатор товара                       SKU_ID          													  #
--  Закупочная стоимость товара         SKU_Purchase_Price      	Закупочная стоимость товара для магазина	  #
--	Розничная стоимость товара			SKU_Retail_Price    Стоимость продажи товара без учета скидок для магазина#
--                            											 				                          #
-- ################################################################################################################
DROP TABLE IF EXISTS Stores;
CREATE TABLE Stores(
	Transaction_Store_ID BIGINT,
	SKU_ID BIGINT NOT NULL,
	SKU_Purchase_Price NUMERIC
	CHECK (SKU_Purchase_Price >= 0),
	SKU_Retail_Price NUMERIC
	CHECK(SKU_Retail_Price >= 0),
	CONSTRAINT fk_sku_id FOREIGN KEY (SKU_ID) REFERENCES ProductGrid(SKU_ID)
);




-- ################################################################################################################
-- Таблица Группы SKU(SKU_Groups)		  																		  #
--																												  #
--        Поле                        Название поля в системе              Описание 							  #
--																												  #
--  Группа SKU			                    Group_ID                   											  #
--  Название группы                         Group_Name         													  #
--																												  #
-- ################################################################################################################
DROP TABLE IF EXISTS SKU_Groups;
CREATE TABLE SKU_Groups(
	Group_ID SERIAL PRIMARY KEY,
    Group_Name VARCHAR(255) CHECK (Group_Name ~ '^[A-Za-zА-Яа-я0-9\s\-\+\=\@\#\$\%\^\&\*\(\)\[\]\{\}\;\:\,\.\<\>\?\/\|\_\~]+$')
);





DROP TABLE IF EXISTS DateAnalysisFormation;
CREATE TABLE DateAnalysisFormation(
	Analysis_Formation TIMESTAMP
);




CREATE OR REPLACE PROCEDURE import_(table_name text, file_path text, delimiter text)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('COPY %I FROM %L WITH CSV DELIMITER %L', table_name, file_path, delimiter);
END;
$$;




CREATE OR REPLACE PROCEDURE export_(table_name text, file_path text, delimiter text)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('COPY %I TO %L WITH CSV DELIMITER %L', table_name, file_path, delimiter);
END;
$$;



--  _____________________________Полный список для импорта датасетс_______________________________


-- CALL import_('personalinformation', '/Users/NAME/Desktop/project/datasets/Personal_Data_Mini.tsv', E'\t');
-- SELECT * FROM personalinformation;


-- CALL import_('cards', '/Users/NAME/Desktop/project/datasets/Cards_Mini.tsv', E'\t');
-- SELECT * FROM cards;

-- SET datestyle = 'ISO, DMY';
-- CALL import_('transactions', '/Users/NAME/Desktop/project/datasets/Transactions_Mini.tsv', E'\t');
-- SELECT * FROM transactions;

-- CALL import_('productgrid', '/Users/NAME/Desktop/project/datasets/SKU_Mini.tsv', E'\t');
-- SELECT * FROM productgrid;

-- CALL import_('checks', '/Users/NAME/Desktop/project/datasets/Checks_Mini.tsv', E'\t');
-- SELECT * FROM checks;

-- CALL import_('stores', '/Users/NAME/Desktop/project/datasets/Stores_Mini.tsv', E'\t');
-- SELECT * FROM Stores;

-- CALL import_('sku_groups', '/Users/NAME/Desktop/project/datasets/Groups_SKU_Mini.tsv', E'\t');
-- SELECT * FROM sku_groups;

-- CALL import_('dateanalysisformation', '/Users/NAME/Desktop/project/datasets/Date_Of_Analysis_Formation.tsv', E'\t');
-- SELECT * FROM dateanalysisformation;

