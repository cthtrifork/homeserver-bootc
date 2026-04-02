FROM docker.io/library/gcc:15@sha256:34214606c5ff7f9f6f0530c0edf7ce30d12ff6ac973fda861e61c92e99f4f607 AS build
RUN printf '%s\n' \
  '#include <stdio.h>' \
  'int main() { printf("Hello%c",0x0A); }' > /hello.c \
 && cc -static /hello.c -o /hello

#FROM scratch
FROM cgr.dev/chainguard/static:latest
COPY --from=build /hello /hello
CMD ["/hello"]
