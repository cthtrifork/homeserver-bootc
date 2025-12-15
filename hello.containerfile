FROM docker.io/library/gcc:6 AS build
RUN printf '%s\n' \
  '#include <stdio.h>' \
  'int main() { printf("Hello%c",0x0A); }' > /hello.c \
 && cc -static /hello.c -o /hello

FROM gcr.io/distroless/cc:nonroot
COPY --from=build /hello /hello
CMD ["/hello"]
