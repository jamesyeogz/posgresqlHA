# Spring Boot PostgreSQL CRUD (Java 21)

This module contains a minimal Spring Boot application using Java 21, Spring Web, Spring Data JPA, and the PostgreSQL driver. It exposes CRUD endpoints for a simple `Book` resource.

## Prerequisites

- Java 21 (JDK)
- Maven 3.9+
- A running PostgreSQL instance

## Configuration

Configure via environment variables (defaults shown):

- `SPRING_DATASOURCE_URL` (default: `jdbc:postgresql://localhost:5432/postgres`)
- `SPRING_DATASOURCE_USERNAME` (default: `postgres`)
- `SPRING_DATASOURCE_PASSWORD` (default: `postgres`)
- `SERVER_PORT` (default: `8080`)

Alternatively, edit `src/main/resources/application.properties`.

## Build & Run

```bash
mvn -q -DskipTests package
java -jar target/spring-app-0.0.1-SNAPSHOT.jar
```

Or run via Maven:

```bash
mvn spring-boot:run
```

## Endpoints

Base path: `http://localhost:8080/api/books`

- `GET /api/books` — list all books
- `GET /api/books/{id}` — get by id
- `POST /api/books` — create
- `PUT /api/books/{id}` — update
- `DELETE /api/books/{id}` — delete

### Example

```bash
# Create
curl -s -X POST http://localhost:8080/api/books \
  -H 'Content-Type: application/json' \
  -d '{"title":"Dune","author":"Frank Herbert","yearPublished":1965}'

# List
curl -s http://localhost:8080/api/books | jq

# Get by id (replace 1 if different)
curl -s http://localhost:8080/api/books/1 | jq

# Update
curl -s -X PUT http://localhost:8080/api/books/1 \
  -H 'Content-Type: application/json' \
  -d '{"title":"Dune (Updated)","author":"Frank Herbert","yearPublished":1965}' | jq

# Delete
curl -s -X DELETE http://localhost:8080/api/books/1 -i
```

## Notes

- `spring.jpa.hibernate.ddl-auto=update` is enabled for convenience. For production, prefer migrations (e.g., Flyway).
- The app uses HikariCP for connection pooling.
