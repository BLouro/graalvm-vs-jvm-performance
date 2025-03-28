CREATE DATABASE demodb;

CREATE USER demo WITH PASSWORD 'demo';

GRANT CONNECT ON DATABASE demodb TO demo;

GRANT USAGE ON SCHEMA public TO demo;



\connect demodb;

CREATE TABLE IF NOT EXISTS books (
    id SERIAL PRIMARY KEY,
    title VARCHAR(150) NOT NULL,
    author VARCHAR(100) NOT NULL,
    price NUMERIC(10,2) NOT NULL
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE books TO demo;

grant all on sequence books_id_seq to demo;

INSERT INTO books (title, author, price) VALUES ('Spring Boot in Action', 'Craig Walls', 45.99);
INSERT INTO books (title, author, price) VALUES ('Clean Code', 'Robert C. Martin', 55.50);
