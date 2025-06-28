# Scripts de Prueba de Caché Semántico para Azure API Management

Este conjunto de scripts PowerShell está diseñado para probar y analizar exhaustivamente el rendimiento del caché semántico en Azure API Management, basándose en la política `apim-policy-embedding-optimized.xml`.

## 📁 Scripts Incluidos

### 1. `test-embedding-cache-v2.ps1`
Script optimizado para probar el caché semántico de embeddings con las siguientes características:
- **Score threshold**: 0.95 (muy estricto, solo matches exactos)
- **TTL**: 7 días para queries, 14 días para documentos/passages
- **Particionamiento**: Por suscripción, deployment, modelo, tipo de input, dimensiones y usuario

### 2. `test-completions-cache-v2.ps1`
Script para probar el caché semántico de chat/completions con:
- **Score threshold**: 0.10 para chat, 0.15 para completions (permisivo)
- **TTL**: Variable según temperatura (1-12 horas)
- **Particionamiento**: Por suscripción, deployment, modelo, grupo de temperatura, max_tokens y usuario

### 3. `analyze-cache-results.ps1`
Script de análisis que procesa los resultados guardados y genera reportes detallados.

## 🚀 Uso Rápido

### Configuración Inicial

```powershell
# Establecer permisos de ejecución (solo la primera vez)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Pruebas de Embeddings

```powershell
# Prueba básica
./test-embedding-cache-v2.ps1 -ApimEndpoint "https://your-apim.azure-api.net/openai" -SubscriptionKey "your-key"

# Prueba completa con resultados guardados
./test-embedding-cache-v2.ps1 -ApimEndpoint "https://your-apim.azure-api.net/openai" `
    -SubscriptionKey "your-key" `
    -DeploymentName "text-embedding-3-large" `
    -ExtendedTests `
    -SaveResults `
    -Verbose

# Prueba de concurrencia con 20 solicitudes paralelas
./test-embedding-cache-v2.ps1 -ApimEndpoint "https://your-apim.azure-api.net/openai" `
    -SubscriptionKey "your-key" `
    -ExtendedTests `
    -BatchSize 20
```

### Pruebas de Chat/Completions

```powershell
# Prueba básica de chat
./test-completions-cache-v2.ps1 -ApimEndpoint "https://your-apim.azure-api.net/openai" `
    -SubscriptionKey "your-key" `
    -DeploymentName "gpt-4"

# Prueba completa incluyendo completions
./test-completions-cache-v2.ps1 -ApimEndpoint "https://your-apim.azure-api.net/openai" `
    -SubscriptionKey "your-key" `
    -DeploymentName "gpt-4" `
    -TestCompletions `
    -ExtendedTests `
    -SaveResults `
    -Verbose
```

### Análisis de Resultados

```powershell
# Analizar todos los resultados en el directorio actual
./analyze-cache-results.ps1

# Comparar múltiples resultados y generar reporte
./analyze-cache-results.ps1 -CompareResults -GenerateReport

# Buscar resultados en un directorio específico
./analyze-cache-results.ps1 -ResultsPath "C:\TestResults" -Pattern "*cache-test*.json"
```

## 📊 Parámetros de los Scripts

### test-embedding-cache-v2.ps1

| Parámetro | Descripción | Valor por Defecto |
|-----------|-------------|-------------------|
| `-ApimEndpoint` | URL del endpoint de API Management | Solicita al usuario |
| `-SubscriptionKey` | Clave de suscripción de APIM | Solicita al usuario |
| `-DeploymentName` | Nombre del deployment de embeddings | text-embedding-3-large |
| `-Verbose` | Muestra información detallada | False |
| `-SaveResults` | Guarda resultados en JSON y CSV | False |
| `-ExtendedTests` | Ejecuta pruebas adicionales | False |
| `-BatchSize` | Número de solicitudes paralelas | 10 |

### test-completions-cache-v2.ps1

| Parámetro | Descripción | Valor por Defecto |
|-----------|-------------|-------------------|
| `-ApimEndpoint` | URL del endpoint de API Management | Solicita al usuario |
| `-SubscriptionKey` | Clave de suscripción de APIM | Solicita al usuario |
| `-DeploymentName` | Nombre del deployment de chat/completions | gpt-4 |
| `-Verbose` | Muestra información detallada | False |
| `-SaveResults` | Guarda resultados en JSON y CSV | False |
| `-ExtendedTests` | Ejecuta pruebas adicionales | False |
| `-TestCompletions` | Incluye pruebas de completions además de chat | False |

### analyze-cache-results.ps1

| Parámetro | Descripción | Valor por Defecto |
|-----------|-------------|-------------------|
| `-ResultsPath` | Directorio donde buscar resultados | . (actual) |
| `-Pattern` | Patrón de archivos a analizar | *cache-test-v2*.json |
| `-GenerateReport` | Genera reporte detallado en Markdown/HTML | False |
| `-CompareResults` | Compara múltiples resultados | False |

## 📈 Métricas Reportadas

### Métricas de Rendimiento
- **Hit Rate**: Porcentaje de solicitudes servidas desde caché
- **Tiempo de Respuesta**: Comparación entre hits y misses
- **Throughput**: Solicitudes por segundo en pruebas de concurrencia
- **Mejora de Velocidad**: Factor de aceleración en cache hits

### Métricas de Costo
- **Tokens Ahorrados**: Estimación basada en cache hits
- **Costo Ahorrado**: Cálculo en USD basado en precios de OpenAI
- **Proyección Mensual**: Estimación de ahorros a 30 días
- **ROI del Caché**: Porcentaje de reducción en costos

### Análisis por Categoría

#### Para Embeddings:
- Estadísticas por tipo: query, document, passage
- Análisis por dimensiones
- Impacto del input_type en el hit rate

#### Para Chat/Completions:
- Estadísticas por grupo de temperatura
- Análisis por max_tokens
- Comparación entre chat y completions

## 🎯 Escenarios de Prueba

### Embeddings

1. **Solicitud Idéntica**: Valida cache hit exacto (threshold 0.95)
2. **Texto Similar**: Prueba que no hay hit con variaciones mínimas
3. **Diferentes Dimensiones**: Valida particionamiento correcto
4. **Tipos de Input**: Compara query vs document vs passage
5. **Metadata y Usuario**: Prueba particionamiento por contexto

### Chat/Completions

1. **Temperatura Determinística**: Máximo cacheo (TTL 12h)
2. **Preguntas Similares**: Valida threshold permisivo (0.10)
3. **Diferentes Temperaturas**: Prueba grupos de TTL
4. **Conversaciones Multi-turno**: Caché de contextos complejos
5. **Parámetros Avanzados**: top_p, penalties, response_format

## 📋 Interpretación de Resultados

### Hit Rate Esperado

| Tipo de Operación | Hit Rate Bajo | Hit Rate Medio | Hit Rate Alto |
|-------------------|---------------|----------------|---------------|
| Embeddings | < 40% | 40-70% | > 70% |
| Chat (temp ≤ 0.2) | < 30% | 30-60% | > 60% |
| Chat (temp > 0.5) | < 20% | 20-40% | > 40% |

### Recomendaciones por Hit Rate

**Hit Rate Bajo (< 30%)**:
- Normalizar entradas antes de procesarlas
- Usar temperaturas más bajas cuando sea posible
- Agrupar parámetros en rangos estándar
- Revisar configuración de thresholds

**Hit Rate Medio (30-60%)**:
- Identificar patrones comunes en consultas
- Pre-computar embeddings frecuentes
- Optimizar prompts del sistema
- Considerar batch processing

**Hit Rate Alto (> 60%)**:
- Sistema optimizado correctamente
- Monitorear tamaño del caché
- Considerar aumentar TTLs
- Evaluar costos de almacenamiento

## 🔧 Solución de Problemas

### Error: "Unauthorized"
- Verificar que la API key sea válida
- Confirmar que el endpoint APIM es correcto
- Revisar permisos de la suscripción

### Error: "Deployment not found"
- Verificar el nombre del deployment
- Confirmar que el modelo está desplegado
- Revisar la versión de la API (api-version)

### Hit Rate 0%
- Verificar configuración de la política APIM
- Confirmar que el caché está habilitado
- Revisar logs de APIM para errores
- Validar que el backend de embeddings funciona

### Timeouts en Pruebas
- Reducir BatchSize en pruebas de concurrencia
- Verificar límites de rate limiting
- Aumentar timeouts en la configuración

## 📊 Ejemplo de Salida

```
╔══════════════════════════════════════════════════════╗
║     🚀 PRUEBA AVANZADA DE CACHÉ SEMÁNTICO v2.0      ║
║              OPTIMIZADA PARA EMBEDDINGS              ║
╚══════════════════════════════════════════════════════╝

📋 CONFIGURACIÓN DE PRUEBAS:
   🔗 Endpoint: https://myapim.azure-api.net/openai
   🎯 Deployment: text-embedding-3-large
   📊 Modo Verbose: True
   🧪 Pruebas Extendidas: True
   📦 Tamaño de Lote: 10
   💾 Guardar Resultados: True

┌─────────────────────────────────────────────────────┐
│ Test 1: Primera solicitud (Query)                    │
└─────────────────────────────────────────────────────┘
✅ Solicitud Exitosa
   ⏱️  Tiempo Total: 245ms (0.25s)
   ⏱️  Tiempo APIM: 243ms
   🔧 Tipo de Operación: embeddings
   📐 Tipo de Embedding: query
   📏 Dimensiones: 3072

   📊 ESTADO DEL CACHÉ:
   ❌ CACHE MISS
   ✓ Resultado esperado confirmado
   ⏰ TTL del Caché: 168 horas
   🔑 Cache Key: emb:text-embedding-3-large|type:query|dim:3072

┌─────────────────────────────────────────────────────┐
│ Test 2: Solicitud idéntica (debe ser HIT)           │
└─────────────────────────────────────────────────────┘
✅ Solicitud Exitosa
   ⏱️  Tiempo Total: 48ms (0.05s)
   ⏱️  Tiempo APIM: 47ms
   🔧 Tipo de Operación: embeddings

   📊 ESTADO DEL CACHÉ:
   🎯 CACHE HIT!
   📈 Score de Similitud: 1.0000
   ✓ Resultado esperado confirmado
   🚀 Mejora de velocidad: 5.1x más rápido

╔══════════════════════════════════════════════════════╗
║              📊 RESUMEN DE RESULTADOS                ║
╚══════════════════════════════════════════════════════╝

📈 ESTADÍSTICAS GENERALES:
   ├─ Total de pruebas: 18
   ├─ ✅ Cache Hits: 7
   ├─ ❌ Cache Misses: 11
   ├─ ⚠️  Errores: 0
   ├─ 📊 Hit Rate Global: 38.89%
   └─ ⏱️  Tiempo promedio: 156.44 ms

💰 ANÁLISIS DE COSTOS:
   ├─ Tokens ahorrados: 1750
   ├─ Costo ahorrado: $0.0002 USD
   ├─ Ahorro proyectado mensual: $0.14 USD
   └─ ROI del caché: 37.0% de reducción en costos

✨ Pruebas de caché semántico para embeddings completadas exitosamente!
```

## 🔗 Recursos Adicionales

- [Documentación de Azure API Management](https://docs.microsoft.com/azure/api-management/)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)
- [Guía de Caché Semántico](https://docs.microsoft.com/azure/api-management/azure-openai-semantic-cache)

## 📝 Notas

- Los scripts requieren PowerShell 5.1 o superior
- Asegúrate de tener conectividad con Azure y OpenAI
- Los resultados pueden variar según la carga del sistema
- Considera ejecutar pruebas en diferentes momentos del día
- Revisa los logs de APIM para información adicional

## 🤝 Contribuciones

Para reportar problemas o sugerir mejoras, por favor crea un issue en el repositorio o contacta al equipo de desarrollo.