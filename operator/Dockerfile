FROM golang:1.22 AS builder

WORKDIR /workspace

COPY go.mod go.sum ./
RUN go mod download

COPY api ./api
COPY config ./config
COPY internal ./internal
COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o /manager .

FROM gcr.io/distroless/static:nonroot

WORKDIR /
COPY --from=builder /manager /manager

USER 65532:65532

ENTRYPOINT ["/manager"]
