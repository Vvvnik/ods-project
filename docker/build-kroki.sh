#!/bin/bash
set -e

# Скрипт для сборки Kroki образа в GitLab Container Registry
# Использование: ./build-kroki.sh [tag]

TAG=${1:-0.28.0}
REGISTRY="registry.gitlab.com/vvvnik/my-project"

echo "🏗️  Сборка Kroki образа для проекта ODS"
echo "📦 Тег: $TAG"
echo "🏪 Реестр: $REGISTRY"
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

echo "📤 Отправка в реестр: $REGISTRY/kroki:$TAG"
docker push "$REGISTRY/kroki:$TAG"

# Удаляем временный файл
rm -f /tmp/Dockerfile.kroki

echo "✅ Образ kroki собран и отправлен"
echo ""
echo "📋 Образ Kroki:"
echo "   - $REGISTRY/kroki:$TAG"
echo ""
echo "💡 Kroki будет доступен в CI как сервис по адресу http://kroki:8000"
