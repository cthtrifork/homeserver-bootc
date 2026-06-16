FROM alpine:3.24@sha256:f5064d3e5f88c467c714509f491853ab2d951932c5cad699c0cb969dcec6f3b4 AS build
RUN apk add --no-cache gcc musl-dev

WORKDIR /app

RUN printf '%s\n' \
  '#include <stdio.h>' \
  'int main() { printf("Hello%c",0x0A); }' > /hello.c \
 && cc -static /hello.c -o /app/hello

FROM scratch

COPY --from=build /app/hello /hello
CMD ["/hello"]
