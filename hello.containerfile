FROM gcc:6 AS build-env
COPY <<EOF /hello.c
#include <stdio.h>
int main() { printf("Hello%c",0x0A); }
EOF
RUN cc -static /hello.c -o /hello

FROM gcr.io/distroless/cc:nonroot
COPY --from=build-env /app /app
WORKDIR /app
CMD ["./hello"]
