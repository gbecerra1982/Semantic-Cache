# Política de Embeddings - Caché Tradicional Optimizado

## 🎯 Características Principales

- **Tipo**: Caché Tradicional con clave manual optimizada
- **TTL Adaptativo**: 1 hora a 7 días según tipo de contenido
- **Rate Limiting**: Dinámico por tipo de operación
- **Batch Support**: Manejo optimizado de arrays de inputs

## 🔧 Funcionalidades Clave

### 1. Detección Automática de Modelo
```xml
<set-variable name="deployment-id" value="@{
    var m = (string)context.Variables["model"];
    if (m == "text-embedding-3-small") { return "text-embedding-3-small"; }
    if (m == "text-embedding-3-large") { return "text-embedding-3-large"; }
    if (m == "text-embedding-ada-002") { return "text-embedding-3-large"; }
    return m;
}" />
```
- Mapeo automático de modelos deprecados
- Fallback a `text-embedding-3-large`

### 2. TTL Adaptativo por Tipo de Contenido
```xml
<set-variable name="cache-ttl" value="@{
    var t = (string)context.Variables["input-type"];
    if (t == "query") { return 3600; }        // 1 hora
    if (t == "document") { return 604800; }   // 7 días
    if (t == "passage") { return 259200; }    // 3 días
    return 86400;                             // 24 horas default
}" />
```

| Tipo | TTL | Razón |
|------|-----|-------|
| `query` | 1 hora | Búsquedas pueden cambiar frecuentemente |
| `document` | 7 días | Documentos estables, embeddings costosos |
| `passage` | 3 días | Fragmentos de texto semi-estables |
| `default` | 24 horas | Balance general |

### 3. Generación de Clave de Caché Inteligente
```xml
<set-variable name="cache-key" value="@{
    var dep   = (string)context.Variables["deployment-id"];
    var mdl   = (string)context.Variables["model"];
    var typ   = (string)context.Variables["input-type"];
    var dim   = (string)context.Variables["dimensions"];
    var sub   = context.Subscription?.Id ?? "public";
    var body  = (JObject)context.Variables["requestBody"];
    var input = body["input"];

    string contentHash = "";
    if (input != null) {
        if (input.Type == JTokenType.String) {
            contentHash = "single:" + input.ToString().GetHashCode();
        }
        else if (input.Type == JTokenType.Array) {
            var arr = (JArray)input;
            var hashes = new System.Text.StringBuilder();
            foreach (var itm in arr) {
                hashes.Append(itm.ToString().GetHashCode()).Append('|');
            }
            contentHash = "batch:" + arr.Count + ":" + hashes.ToString().GetHashCode();
        }
    }

    var meta = body["metadata"];
    var metaHash = meta != null ? ":meta:" + meta.ToString().GetHashCode() : "";

    return "emb:v2:" + dep + ":" + mdl + ":" + typ + ":" + dim + ":" + sub + ":" + contentHash + metaHash;
}" />
```

**Estructura de la clave**:
```
emb:v2:{deployment}:{model}:{input_type}:{dimensions}:{subscription}:{content_hash}{metadata_hash}
```

### 4. Manejo de Operaciones Batch
```xml
<set-variable name="is-batch" value="@{
    var input = ((JObject)context.Variables["requestBody"])["input"];
    return input != null && input.Type == JTokenType.Array;
}" />

<set-variable name="batch-size" value="@{
    var arr = ((JObject)context.Variables["requestBody"])["input"] as JArray;
    return arr != null ? arr.Count : 1;
}" />
```

### 5. Rate Limiting Dinámico
```xml
<rate-limit-by-key 
    calls="@(((bool)context.Variables["is-batch"]) ? 100 : 1000)" 
    renewal-period="60" 
    counter-key="@(context.Subscription?.Id ?? context.Request.IpAddress)" />
```
- **Batch operations**: 100 calls/minuto
- **Single operations**: 1000 calls/minuto

### 6. Respuesta Inmediata en Cache Hit
```xml
<choose>
    <when condition="@(context.Variables.ContainsKey("cached-response") && context.Variables["cached-response"] != null)">
        <set-variable name="cache-status" value="HIT" />
        <return-response>
            <set-status code="200" reason="OK" />
            <!-- Headers y respuesta cacheada -->
        </return-response>
    </when>
</choose>
```

### 7. Headers de Monitoreo
- `X-Cache-Status`: HIT/MISS
- `X-Model-Version`: Modelo utilizado
- `X-Deployment-Used`: Deployment real
- `X-Batch-Size`: Tamaño del batch
- `X-Processing-Time-Ms`: Tiempo de procesamiento
- `X-Cache-TTL`: TTL aplicado

## ✅ Beneficios

1. **Eficiencia**: Evita recálculo de embeddings idénticos
2. **Flexibilidad**: TTL adaptativo por tipo de contenido
3. **Escalabilidad**: Rate limiting dinámico
4. **Robustez**: Manejo de errores estructurado
5. **Observabilidad**: Métricas detalladas de rendimiento

## 🎯 Casos de Uso Ideales

- Sistemas de búsqueda semántica con documentos estables
- Procesamiento de embeddings para knowledge bases
- APIs que manejan tanto queries como documentos
- Sistemas que requieren embeddings batch de alta frecuencia