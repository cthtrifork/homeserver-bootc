FROM docker.io/library/gcc:15@sha256:27be068a2580bed7c32ccf2349352e29f86e0a5c8cda8c9c98c6b59e4ad98d53 AS build
RUN printf '%s\n' \
  '#include <stdio.h>' \
  'int main() { printf("Hello%c",0x0A); }' > /hello.c \
 && cc -static /hello.c -o /hello

#FROM scratch
FROM cgr.dev/chainguard/static:latest
COPY --from=build /hello /hello
CMD ["/hello"]
