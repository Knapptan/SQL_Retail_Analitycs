-- SELECT current_database(); - узнаем имя нашей базы

-- Внесите в скрипт part3.sql создание ролей и выдачу им прав в соответствии с описанным ниже.

-- Администратор
-- Администратор имеет полные права на редактирование и просмотр любой информации, запуск и остановку процесса обработки.

-- Посетитель
-- Только просмотр информации из всех таблиц.

-- Создаем роль "Администратор"
CREATE ROLE admin WITH LOGIN PASSWORD '2121';
-- Выдаем ему права на все таблицы нашей базы 
GRANT ALL PRIVILEGES ON DATABASE "retail" TO admin;
GRANT ALL PRIVILEGES ON SCHEMA public TO admin;
ALTER ROLE admin CREATEDB CREATEROLE;

-- Создаем роль "Посетитель"
CREATE ROLE visitor WITH LOGIN PASSWORD '2121';
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO visitor;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO visitor;
-- Чтобы автоматически давать права на чтение для всех будущих таблиц
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO visitor;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO visitor;