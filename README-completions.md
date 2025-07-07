# Política de Completions - Caché Semántico

## 🎯 Características Principales

- **Tipo**: Caché Semántico Azure OpenAI
- **Score Threshold**: 0.10 (flexible - permite respuestas similares)
- **TTL**: 2 horas (7200 segundos)
- **Backend**: `text-embedding-3-large` para embeddings semánticos

## 🔧 Funcionalidades Clave

### 1. Extracción de Parámetros
```xml
<set-variable name="temperature" value="@{
    var body = (JObject)context.Variables[&quot;requestBody&quot;];
    return body[&quot;temperature&quot;]?.Value<float>()?? 0.7f;
}" />
```
- Extrae: `temperature`, `max_tokens`, `model`, `user`, `top_p`, `frequency_penalty`, `presence_penalty`
- Valores por defecto para parámetros faltantes

### 2. Agrupación Inteligente por Temperatura
```xml
<set-variable name="temperature-group" value="@{
    var temp = (float)context.Variables[&quot;temperature&quot;];
    if (temp <= 0.2) { return &quot;deterministic&quot;; }
    else if (temp <= 0.5) { return &quot;low&quot;; }
    else if (temp <= 0.8) { return &quot;medium&quot;; }
    else { return &quot;high&quot;; }
}" />
```

| Grupo | Rango | Comportamiento | TTL Recomendado |
|-------|-------|----------------|------------------|
| `deterministic` | 0.0 - 0.2 | Respuestas consistentes | 12 horas |
| `low` | 0.2 - 0.5 | Variación mínima | 4 horas |
| `medium` | 0.5 - 0.8 | Variación moderada | 2 horas |
| `high` | 0.8+ | Alta creatividad | 1 hora |

### 3. Particionamiento Avanzado
El caché se particiona por múltiples dimensiones:

- **Suscripción**: `@(context.Subscription?.Id ?? "public")`
- **Modelo**: `@(context.Variables.GetValueOrDefault("model", "gpt-4"))`
- **Grupo de temperatura**: Para optimizar hits por comportamiento
- **Rango de tokens**: Agrupa por `small`, `medium`, `large`, `xlarge`
- **Usuario**: Separa por usuario si se proporciona
- **Penalizaciones**: Agrupa `frequency_penalty` y `presence_penalty`
- **System message**: Hash del mensaje de sistema
- **Funciones/Herramientas**: Hash de functions o tools

### 4. Headers de Monitoreo
```xml
<set-header name="X-Semantic-Cache-Status" exists-action="override">
    <value>@{
        var status = context.Variables.GetValueOrDefault("semantic-cache-lookup-status", "none");
        return status.ToString().ToUpper();
    }</value>
</set-header>
```

**Headers disponibles**:
- `X-Semantic-Cache-Status`: HIT/MISS
- `X-Semantic-Cache-Score`: Score de similitud semántica
- `X-Temperature-Group`: Clasificación de temperatura
- `X-Recommended-TTL-Hours`: TTL sugerido por temperatura
- `X-Cache-Optimization-Tip`: Consejos de optimización

## ✅ Beneficios

1. **Flexibilidad**: Threshold bajo permite reutilizar respuestas similares
2. **Inteligencia**: Agrupa por comportamiento esperado (temperatura)
3. **Escalabilidad**: Particionamiento evita colisiones entre usuarios
4. **Observabilidad**: Headers extensivos para monitoreo
5. **Optimización**: TTL adaptativo según parámetros

## 🎯 Casos de Uso Ideales

- Chatbots con consultas frecuentes similares
- APIs de Q&A con variaciones mínimas en preguntas
- Sistemas que procesan consultas con baja temperatura
- Aplicaciones que requieren respuestas rápidas para consultas similares