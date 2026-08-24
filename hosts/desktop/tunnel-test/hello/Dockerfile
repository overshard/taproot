FROM golang:1-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /hello .

FROM scratch
COPY --from=build /hello /hello
ENV GO_HELLO_TAG=tunnel-test
EXPOSE 8000
ENTRYPOINT ["/hello"]
