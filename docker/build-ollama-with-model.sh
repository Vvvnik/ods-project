#!/bin/bash
set -e

# Скрипт для сборки Ollama образа с предзагруженной моделью в GitLab Container Registry
# Использование: ./build-ollama-with-model.sh [tag] [model] [--push|--no-push]
#   tag - тег образа (по умолчанию: 1)
#   model - название модели (по умолчанию: gemma:latest)
#   --push - отправить образ в реестр (по умолчанию)
#   --no-push - только собрать образ, не отправлять в реестр
#
# Примечание: Модель загружается во время сборки образа
# Размер образа будет больше, но модель будет доступна сразу при запуске

TAG=1
MODEL="gemma:latest"
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
      # Если аргумент не флаг, то это тег или модель
      if [[ "$arg" =~ ^[0-9]+$ ]] || [[ "$arg" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        # Если тег еще не установлен, это тег, иначе это модель
        if [[ "$TAG" == "1" ]] && [[ "$arg" != "gemma:latest" ]]; then
          TAG="$arg"
        else
          MODEL="$arg"
        fi
      fi
      ;;
  esac
done

REGISTRY="registry.gitlab.com/vvvnik/ods-project"

echo "🏗️  Сборка Ollama образа с моделью для проекта ODS"
echo "📦 Тег: $TAG"
echo "🤖 Модель: $MODEL"
echo "🏪 Реестр: $REGISTRY"
if [[ "$PUSH" == "true" ]]; then
  echo "📤 Режим: сборка и отправка в реестр"
else
  echo "📤 Режим: только сборка (без отправки в реестр)"
fi
echo ""
echo "⚠️  Внимание: Размер образа будет большим (10+ GB) из-за предзагруженной модели"
echo ""

# Создаем временный Dockerfile для Ollama с моделью
cat > /tmp/Dockerfile.ollama-model << EOF
FROM ollama/ollama:latest

# Загружаем модель во время сборки образа
# Это делает образ самодостаточным, но увеличивает его размер
RUN ollama pull $MODEL

EXPOSE 11434

CMD ["ollama", "serve"]
EOF

echo "🔨 Сборка образа: ollama с моделью $MODEL"
echo "   Базовый образ: ollama/ollama:latest"
echo "   Модель будет предзагружена в образ"

docker build -t "$REGISTRY/ollama:$TAG" -f /tmp/Dockerfile.ollama-model .

if [[ "$PUSH" == "true" ]]; then
  echo "📤 Отправка в реестр: $REGISTRY/ollama:$TAG"
  echo "⚠️  Это может занять много времени из-за большого размера образа..."
  docker push "$REGISTRY/ollama:$TAG"
  echo "✅ Образ ollama с моделью собран и отправлен"
else
  echo "✅ Образ ollama с моделью собран (локально, без отправки в реестр)"
fi

# Удаляем временный файл
rm -f /tmp/Dockerfile.ollama-model

if [[ "$PUSH" == "true" ]]; then
  echo "🎉 Образ успешно собран и отправлен в реестр!"
else
  echo "🎉 Образ успешно собран локально!"
fi
echo ""
echo "📋 Образ Ollama с моделью:"
echo "   - $REGISTRY/ollama:$TAG"
echo "   - Модель: $MODEL"
if [[ "$PUSH" == "false" ]]; then
  echo ""
  echo "💡 Для отправки в реестр запустите:"
  echo "   docker push $REGISTRY/ollama:$TAG"
fi
echo ""
echo "💡 Ollama будет доступен в CI как сервис по адресу http://ollama:11434"
echo "💡 Модель $MODEL уже предзагружена и готова к использованию"

