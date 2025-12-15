FROM docker.io/library/gcc:6 AS build
RUN printf '%s\n' \
  '#include <stdio.h>' \
  'int main() { printf("Hello%c",0x0A); }' > /hello.c \
 && cc -static /hello.c -o /hello

#FROM scratch
FROM cgr.dev/chainguard/static:latest
COPY --from=build /hello /hello
CMD ["/hello"]
