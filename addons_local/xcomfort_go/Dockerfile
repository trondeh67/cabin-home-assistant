# ARG må erklæres før første FROM hvis den brukes i FROM
ARG BUILD_FROM

# ---- Stage 1: build xcomfortd-go ----
FROM golang:1.22-alpine AS build
RUN apk add --no-cache git libusb-dev eudev-dev pkgconfig build-base linux-headers
ENV CGO_ENABLED=1
WORKDIR /src
RUN git clone --depth 1 https://github.com/karloygard/xcomfortd-go .
RUN go build -ldflags="-w -s" -o /out/xcomfortd-go .

# ---- Stage 2: runtime på Home Assistant base ----
FROM ${BUILD_FROM}

RUN apk add --no-cache tzdata libusb eudev-libs jq

# Binær + startscript + ev. rootfs (men vi bruker ikke services.d nå)
COPY --from=build /out/xcomfortd-go /usr/local/bin/xcomfortd-go
COPY start.sh /usr/local/bin/start.sh
COPY rootfs/ /  

# Viktig: ikke rør ENTRYPOINT; sett kun CMD til vårt startscript
CMD ["/usr/local/bin/start.sh"]
