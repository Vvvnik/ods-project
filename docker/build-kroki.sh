#!/bin/bash
set -e

# Скрипт для сборки Kroki образа в GitLab Container Registry
# Использование: ./build-kroki.sh [tag] [--push|--no-push]
#   tag - тег образа (по умолчанию: 0.28.0)
#   --push - отправить образ в реестр (по умолчанию)
#   --no-push - только собрать образ, не отправлять в реестр

TAG=0.28.0
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
      if [[ "$arg" =~ ^[0-9.]+$ ]] || [[ "$arg" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        TAG="$arg"
      fi
      ;;
  esac
done

REGISTRY="registry.gitlab.com/vvvnik/ods-project"

echo "🏗️  Сборка Kroki образа для проекта ODS"
echo "📦 Тег: $TAG"
echo "🏪 Реестр: $REGISTRY"
if [[ "$PUSH" == "true" ]]; then
  echo "📤 Режим: сборка и отправка в реестр"
else
  echo "📤 Режим: только сборка (без отправки в реестр)"
fi
echo ""

# Создаем временный Dockerfile для Kroki
cat > /tmp/Dockerfile.kroki << 'EOF'
FROM yuzutech/kroki:0.28.0

# Kroki уже настроен и готов к работе
# Дополнительная настройка не требуется

EXPOSE 8000

CMD ["kroki"]
EOF

echo "🔨 Сборка образа: kroki"
echo "   Базовый образ: yuzutech/kroki:0.28.0"

docker build -t "$REGISTRY/kroki:$TAG" -f /tmp/Dockerfile.kroki .

if [[ "$PUSH" == "true" ]]; then
  echo "📤 Отправка в реестр: $REGISTRY/kroki:$TAG"
  docker push "$REGISTRY/kroki:$TAG"
  echo "✅ Образ kroki собран и отправлен"
else
  echo "✅ Образ kroki собран (локально, без отправки в реестр)"
fi

# Удаляем временный файл
rm -f /tmp/Dockerfile.kroki

if [[ "$PUSH" == "true" ]]; then
  echo "🎉 Образ успешно собран и отправлен в реестр!"
else
  echo "🎉 Образ успешно собран локально!"
fi
echo ""
echo "📋 Образ Kroki:"
echo "   - $REGISTRY/kroki:$TAG"
if [[ "$PUSH" == "false" ]]; then
  echo ""
  echo "💡 Для отправки в реестр запустите:"
  echo "   docker push $REGISTRY/kroki:$TAG"
fi
echo ""
echo "💡 Kroki будет доступен в CI как сервис по адресу http://kroki:8000"
