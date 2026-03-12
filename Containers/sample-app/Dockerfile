# Build Stage
FROM node:25 AS builder
WORKDIR /build
COPY package.json ./
RUN npm install
COPY app.js ./

# Runtime Stage with Distroless
FROM gcr.io/distroless/nodejs20-debian12

# Create non-root user (if not in distroless base)
# RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app
COPY --from=builder /build/node_modules ./node_modules
COPY --from=builder /build/app.js ./

# Switch to non-root user (if applicable)
# USER appuser

EXPOSE 3000
CMD ["app.js"]