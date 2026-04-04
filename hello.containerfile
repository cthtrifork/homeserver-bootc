FROM alpine:3.23 AS build
RUN apk add --no-cache gcc musl-dev

WORKDIR /app

RUN printf '%s\n' \
  '#include <stdio.h>' \
  'int main() { printf("Hello%c",0x0A); }' > /hello.c \
 && cc -static /hello.c -o /app/hello

FROM scratch

COPY --from=build /app/hello /hello
CMD ["/hello"]
