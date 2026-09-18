FROM alpine:3.24@sha256:5b02b42e375f7426f8d65c3af331ca05d9878f9989230354504e0b9dfd431f60 AS build
RUN apk add --no-cache gcc musl-dev

WORKDIR /app

RUN printf '%s\n' \
  '#include <stdio.h>' \
  'int main() { printf("Hello%c",0x0A); }' > /hello.c \
 && cc -static /hello.c -o /app/hello

FROM scratch

COPY --from=build /app/hello /hello
CMD ["/hello"]
