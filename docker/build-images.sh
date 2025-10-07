#!/bin/bash
set -e

# Скрипт для сборки универсального Docker образа в GitLab Container Registry
# Использование: ./build-images.sh [tag]

TAG=${1:-1}
REGISTRY="registry.gitlab.com/vvvnik/my-project"

echo "🏗️  Сборка универсального Docker образа для проекта ODS"
echo "📦 Тег: $TAG"
echo "🏪 Реестр: $REGISTRY"
echo ""

# Переходим в корень проекта
cd "$(dirname "$0")/.."

echo "🔨 Сборка универсального образа: ruby-node-antora"
echo "   Dockerfile: .ci/Dockerfile.universal"
echo "   Контекст: ."

docker build -f .ci/Dockerfile.universal -t "$REGISTRY/ruby-node-antora:$TAG" .

echo "📤 Отправка в реестр: $REGISTRY/ruby-node-antora:$TAG"
docker push "$REGISTRY/ruby-node-antora:$TAG"

echo "✅ Универсальный образ собран и отправлен"
echo ""
echo "🎉 Образ успешно собран и отправлен в реестр!"
echo ""
echo "📋 Список образов:"
echo "   - $REGISTRY/ruby-node-antora:$TAG"
echo ""
echo "💡 Универсальный образ содержит Ruby + Node.js + все необходимые пакеты"
echo "💡 Для использования в CI обновите тег в .gitlab-ci.yml"
