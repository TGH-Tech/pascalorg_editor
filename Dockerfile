# syntax=docker/dockerfile:1

##############################################################################
# Base — shared image for all stages
##############################################################################
FROM oven/bun:1.3.0-alpine AS base

##############################################################################
# Deps — install workspace dependencies
# Copies only package manifests so this layer is cached until
# bun.lock or any package.json changes (not on source file changes).
##############################################################################
FROM base AS deps
WORKDIR /app

COPY package.json bun.lock ./

# Copy every workspace package manifest
COPY apps/editor/package.json                ./apps/editor/package.json
COPY packages/core/package.json              ./packages/core/package.json
COPY packages/editor/package.json            ./packages/editor/package.json
COPY packages/viewer/package.json            ./packages/viewer/package.json
COPY packages/ui/package.json                ./packages/ui/package.json
COPY packages/eslint-config/package.json     ./packages/eslint-config/package.json
COPY packages/typescript-config/package.json ./packages/typescript-config/package.json
COPY tooling/typescript/package.json         ./tooling/typescript/package.json

RUN bun install --frozen-lockfile

##############################################################################
# Builder — compile packages and the Next.js app via Turborepo
##############################################################################
FROM base AS builder
WORKDIR /app

# Bring in pre-installed external packages from the deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy full source (node_modules excluded via .dockerignore)
COPY . .

# Re-link workspace packages into node_modules (fast — lockfile unchanged)
RUN bun install --frozen-lockfile

# Skip run-time env validation — real values are injected at container start
ENV SKIP_ENV_VALIDATION=1

RUN bun run build

##############################################################################
# Runner — minimal production image, only the Next.js standalone bundle
##############################################################################
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production

# Non-root user for security
RUN addgroup -g 1001 -S nodejs \
 && adduser  -S nextjs -u 1001

# Next.js standalone server (includes its own minimal node_modules)
COPY --from=builder --chown=nextjs:nodejs /app/apps/editor/.next/standalone ./

# Pre-compiled client assets
COPY --from=builder --chown=nextjs:nodejs /app/apps/editor/.next/static ./apps/editor/.next/static

# Static public folder (icons, images, audio, 3D assets, etc.)
COPY --from=builder --chown=nextjs:nodejs /app/apps/editor/public ./apps/editor/public

USER nextjs

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

CMD ["node", "apps/editor/server.js"]
