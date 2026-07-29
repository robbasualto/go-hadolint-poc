FROM golang:latest

RUN apt-get update && apt-get install -y curl

ADD . /app
WORKDIR /app

RUN go build -o server main.go

CMD go run main.go
