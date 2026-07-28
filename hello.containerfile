FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS build
RUN apk add --no-cache gcc musl-dev

WORKDIR /app

RUN printf '%s\n' \
  '#include <stdio.h>' \
  'int main() { printf("Hello%c",0x0A); }' > /hello.c \
 && cc -static /hello.c -o /app/hello

FROM scratch

COPY --from=build /app/hello /hello
CMD ["/hello"]
