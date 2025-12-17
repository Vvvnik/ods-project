#!/bin/bash
set -e

# Скрипт для сборки универсального Docker образа в GitLab Container Registry
# Использование: ./build-images.sh [tag] [--push|--no-push]
#   tag - тег образа (по умолчанию: 1)
#   --push - отправить образ в реестр (по умолчанию)
#   --no-push - только собрать образ, не отправлять в реестр

TAG=1
PUSH=true

# Обработка аргументов
for arg in "$@"; do
  case $arg in
    --push)
      PUSH=true
      ;;
    --no-push)
      PUSH=false
      ;;
    *)
      # Если аргумент не флаг, то это тег
      if [[ "$arg" =~ ^[0-9]+$ ]] || [[ "$arg" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        TAG="$arg"
      fi
      ;;
  esac
done

REGISTRY="registry.gitlab.com/vvvnik/ods-project"

echo "🏗️  Сборка универсального Docker образа для проекта ODS"
echo "📦 Тег: $TAG"
echo "🏪 Реестр: $REGISTRY"
if [[ "$PUSH" == "true" ]]; then
  echo "📤 Режим: сборка и отправка в реестр"
else
  echo "📤 Режим: только сборка (без отправки в реестр)"
fi
echo ""

# Переходим в корень проекта
cd "$(dirname "$0")/.."

echo "🔨 Сборка универсального образа: ruby-node-antora"
echo "   Dockerfile: docker/Dockerfile.universal"
echo "   Контекст: ."

docker build -f docker/Dockerfile.universal -t "$REGISTRY/ruby-node-antora:$TAG" .

if [[ "$PUSH" == "true" ]]; then
  echo "📤 Отправка в реестр: $REGISTRY/ruby-node-antora:$TAG"
  docker push "$REGISTRY/ruby-node-antora:$TAG"
  echo "✅ Универсальный образ собран и отправлен"
else
  echo "✅ Универсальный образ собран (локально, без отправки в реестр)"
fi
echo ""
if [[ "$PUSH" == "true" ]]; then
  echo "🎉 Образ успешно собран и отправлен в реестр!"
else
  echo "🎉 Образ успешно собран локально!"
fi
echo ""
echo "📋 Образ:"
echo "   - $REGISTRY/ruby-node-antora:$TAG"
if [[ "$PUSH" == "false" ]]; then
  echo ""
  echo "💡 Для отправки в реестр запустите:"
  echo "   docker push $REGISTRY/ruby-node-antora:$TAG"
fi
echo ""
echo "💡 Универсальный образ содержит Ruby + Node.js + все необходимые пакеты"
echo "💡 Для использования в CI обновите тег в .gitlab-ci.yml"
