FROM golang:1.26.5-bookworm AS build

WORKDIR /app

COPY go.mod ./
COPY main.go ./

RUN go build -o server main.go

FROM gcr.io/distroless/base-debian12:nonroot

WORKDIR /app

COPY --from=build /app/server ./server

USER nonroot:nonroot

ENTRYPOINT ["./server"]
