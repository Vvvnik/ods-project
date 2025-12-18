#!/bin/bash
set -e

# Скрипт для сборки Ollama образа в GitLab Container Registry
# Использование: ./build-ollama.sh [tag] [--push|--no-push]
#   tag - тег образа (по умолчанию: 1)
#   --push - отправить образ в реестр (по умолчанию)
#   --no-push - только собрать образ, не отправлять в реестр
#
# Примечание: Модель загружается при запуске контейнера
# Для образа с предзагруженной моделью используйте build-ollama-with-model.sh

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

echo "🏗️  Сборка Ollama образа для проекта ODS"
echo "📦 Тег: $TAG"
echo "🏪 Реестр: $REGISTRY"
if [[ "$PUSH" == "true" ]]; then
  echo "📤 Режим: сборка и отправка в реестр"
else
  echo "📤 Режим: только сборка (без отправки в реестр)"
fi
echo ""

# Создаем временный Dockerfile для Ollama
cat > /tmp/Dockerfile.ollama << 'EOF'
FROM ollama/ollama:latest

# Ollama уже настроен и готов к работе
# Модель будет загружена при запуске контейнера

EXPOSE 11434

CMD ["ollama", "serve"]
EOF

echo "🔨 Сборка образа: ollama"
echo "   Базовый образ: ollama/ollama:latest"
echo "   Примечание: Модель загружается при запуске контейнера"

docker build -t "$REGISTRY/ollama:$TAG" -f /tmp/Dockerfile.ollama .

if [[ "$PUSH" == "true" ]]; then
  echo "📤 Отправка в реестр: $REGISTRY/ollama:$TAG"
  docker push "$REGISTRY/ollama:$TAG"
  echo "✅ Образ ollama собран и отправлен"
else
  echo "✅ Образ ollama собран (локально, без отправки в реестр)"
fi

# Удаляем временный файл
rm -f /tmp/Dockerfile.ollama

if [[ "$PUSH" == "true" ]]; then
  echo "🎉 Образ успешно собран и отправлен в реестр!"
else
  echo "🎉 Образ успешно собран локально!"
fi
echo ""
echo "📋 Образ Ollama:"
echo "   - $REGISTRY/ollama:$TAG"
if [[ "$PUSH" == "false" ]]; then
  echo ""
  echo "💡 Для отправки в реестр запустите:"
  echo "   docker push $REGISTRY/ollama:$TAG"
fi
echo ""
echo "💡 Ollama будет доступен в CI как сервис по адресу http://ollama:11434"
echo "💡 Для образа с предзагруженной моделью используйте: ./build-ollama-with-model.sh"

