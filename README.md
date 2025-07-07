# 🚀 Políticas de Caché Inteligente para Azure OpenAI

Implementación de políticas de caché optimizadas para Azure API Management que reducen costos hasta un 90% y mejoran el rendimiento hasta 20x mediante estrategias diferenciadas para Completions (caché semántico) y Embeddings (caché tradicional optimizado) usando **Azure Managed Redis**.

## 📋 Tabla de Contenidos

- [Arquitectura del Sistema](#-arquitectura-del-sistema)
- [Análisis de Políticas](#-análisis-de-políticas)
- [Prerrequisitos](#-prerrequisitos)
- [Implementación Paso a Paso](#-implementación-paso-a-paso)
- [Configuración de Azure Managed Redis](#-configuración-de-azure-managed-redis)
- [Validación y Testing](#-validación-y-testing)
- [Monitoreo y Métricas](#-monitoreo-y-métricas)
- [Mejores Prácticas](#-mejores-prácticas)

## 🏗 Arquitectura del Sistema

```mermaid
graph TB
    subgraph "Cliente"
        A[Aplicación/Usuario]
        B[SDK OpenAI/HTTP Client]
    end
    
    subgraph "Azure API Management"
        C[API Gateway]
        D[Política de Caché Inteligente]
        E{Router por Operación}
        F[Política Embeddings<br/>Caché Tradicional + TTL Adaptativo]
        G[Política Completions<br/>Caché Semántico + Threshold 0.10]
    end
    
    subgraph "Caché Layer"
        H[(Caché Interno APIM)]
        I[Búsqueda Semántica]
        J[Almacenamiento con TTL]
        R[(Azure Managed Redis)]
    end
    
    subgraph "Azure AI Foundry"
        K[AI Foundry Gateway]
        L[Deployment Manager]
        M[text-embedding-3-large]
        N[GPT-4/GPT-4o]
    end
    
    subgraph "Métricas"
        O[Application Insights]
        P[Log Analytics]
        Q[Dashboards]
    end
    
    A --> B
    B --> C
    C --> D
    D --> E
    E -->|Embeddings| F
    E -->|Chat/Completions| G
    
    F --> H
    G --> I
    
    I -->|Cache Hit Semántico| H
    H -->|Cache Hit Tradicional| R
    I -->|Cache Miss| K
    H -->|Cache Miss| K
    
    R -->|Return Cached| A
    
    K --> L
    L --> M
    L --> N
    
    M -->|Store Result| J
    N -->|Store Result| J
    J --> H
    H -->|Persist| R
    
    D --> O
    O --> P
    P --> Q
    
    style C fill:#0078D4,stroke:#fff,stroke-width:2px
    style D fill:#FF6B6B,stroke:#fff,stroke-width:2px
    style F fill:#51CF66,stroke:#000,stroke-width:2px,color:#000
    style G fill:#845EF7,stroke:#fff,stroke-width:2px
    style H fill:#51CF66,stroke:#000,stroke-width:2px,color:#000
    style R fill:#DC382D,stroke:#fff,stroke-width:2px
    style K fill:#FFA94D,stroke:#fff,stroke-width:2px
    style M fill:#845EF7,stroke:#fff,stroke-width:2px
    style N fill:#845EF7,stroke:#fff,stroke-width:2px
```

## 🔍 Análisis de Políticas

### 📊 Comparación de Estrategias

| Característica | Política Completions | Política Embeddings |
|----------------|---------------------|-------------------|
| **Tipo de Caché** | Semántico Azure OpenAI | Tradicional optimizado |
| **Threshold** | 0.10 (flexible) | N/A (hash exacto) |
| **TTL** | Fijo 2 horas | Adaptativo 1h - 7 días |
| **Particionamiento** | 8 dimensiones | 6 dimensiones |
| **Rate Limiting** | No | Sí (dinámico) |
| **Batch Support** | Implícito | Explícito |
| **Hit Rate Esperado** | 30-60% | 80-95% |
| **Persistencia** | Azure Managed Redis | Azure Managed Redis |

### 🎯 Política de Completions - Caché Semántico

**Características principales**:
- **Score Threshold**: 0.10 - Permite respuestas similares
- **TTL**: 2 horas fijas
- **Agrupación por temperatura**: Optimiza hits por comportamiento
- **Particionamiento inteligente**: Evita colisiones entre contextos
- **Backend**: Azure Managed Redis para persistencia

**Casos de uso ideales**:
- Chatbots con consultas frecuentes similares
- APIs de Q&A con variaciones mínimas
- Sistemas con baja temperatura (respuestas consistentes)

### 🎯 Política de Embeddings - Caché Tradicional Optimizado

**Características principales**:
- **TTL Adaptativo**: 1 hora (queries) a 7 días (documentos)
- **Detección de batch**: Optimiza operaciones masivas
- **Rate limiting dinámico**: 100 calls/min (batch) vs 1000 calls/min (single)
- **Clave inteligente**: Hash de contenido + metadatos
- **Persistencia**: Azure Managed Redis con alta durabilidad

**Casos de uso ideales**:
- Sistemas de búsqueda semántica
- Knowledge bases con documentos estables
- Procesamiento batch de embeddings

## 📋 Prerrequisitos

### 🔧 Infraestructura Requerida

1. **Azure API Management**
   - Tier: Standard, Premium, o Developer
   - Managed Identity habilitada

2. **Azure OpenAI Service o Azure AI Foundry**
   - Deployments configurados:
     - `gpt-4` o `gpt-4o` para completions
     - `text-embedding-3-large` para embeddings semánticos

3. **Azure Managed Redis**
   - Tier: Standard o Premium recomendado
   - SSL/TLS habilitado
   - Configuración de red compatible con APIM

4. **Application Insights** (Opcional)
   - Para monitoreo avanzado y métricas

### 🔑 Permisos Necesarios

```bash
# Roles requeridos en Azure
- API Management Service Contributor
- Cognitive Services User (en OpenAI/AI Foundry)
- Redis Cache Contributor (en Azure Managed Redis)
```

## 🚀 Implementación Paso a Paso

### Paso 1: Configurar Infraestructura Base

#### 1.1 Crear Azure API Management

1. **Crear API Management**:
   ```bash
   az apim create \
     --name "apim0-m5gd7y67cu5b6" \
     --resource-group "rg-gpt-rag-model-standard" \
     --publisher-name "Tu Organización" \
     --publisher-email "admin@tudominio.com" \
     --sku-name "Standard"
   ```

2. **Habilitar Managed Identity**:
   ```bash
   az apim identity assign \
     --name "apim0-m5gd7y67cu5b6" \
     --resource-group "rg-gpt-rag-model-standard"
   ```

#### 1.2 Crear Azure Managed Redis

1. **Crear Azure Managed Redis**:
   ```bash
   az redis create \
     --name "redis-cache-apim" \
     --resource-group "rg-gpt-rag-model-standard" \
     --location "North Central US" \
     --sku "Standard" \
     --vm-size "C3" \
     --enable-non-ssl-port false
   ```

2. **Obtener configuración de Redis**:
   ```bash
   # Obtener connection string
   az redis list-keys --name "redis-cache-apim" --resource-group "rg-gpt-rag-model-standard"
   
   # Obtener endpoint
   az redis show --name "redis-cache-apim" --resource-group "rg-gpt-rag-model-standard" --query "hostName"
   ```

#### 1.3 Configurar External Cache en API Management

1. **En Azure Portal → API Management → External cache**:
   ```
   Deployment + infrastructure → External cache → + Add
   ├── Cache instance: redis-cache-apim
   ├── Cache instance location: North Central US  
   ├── Use from: North Central US (managed)
   ├── Description: Azure Managed Redis for APIM Cache
   └── Connection string: [Tu connection string de Redis]
   ```

2. **Verificar la conexión**:
   - El status debe aparecer como "Connected"
   - Redis debe estar disponible para las políticas de caché

### Paso 2: Importar API de Azure AI Foundry

1. **En Azure Portal → API Management → APIs**:
   ```
   + Add API → Create from Azure resource → Azure AI Foundry
   ├── Display name: AOAI
   ├── Name: aoai
   ├── AI service: Selecciona tu recurso Azure AI Foundry
   ├── API URL suffix: aoai/models
   ├── Base URL: https://apim0-m5gd7y67cu5b6.azure-api.net/aoai/models
   └── Create
   ```

2. **Verificar operaciones importadas principales**:
   - `POST` - **Return the embedding vectors for given text prompts**
   - `POST` - **Gets chat completions for the provided chat messages**
   - `POST` - Generates an image based on a text or image prompt
   - `POST` - Return the embedding vectors for given images
   - `GET` - Returns information about the AI model deployed

### Paso 3: Aplicar Política de Completions

1. **Navegar a la operación**:
   ```
   APIs → AOAI → All operations → 
   "Gets chat completions for the provided chat messages" → Inbound processing
   ```

2. **Entrar al editor de políticas** (icono `</>`):

3. **Reemplazar todo el contenido con**:
   ```xml
   <policies>
       <inbound>
           <base />
           
           <!-- Extraer y validar el request body -->
           <set-variable name="requestBody" value="@(context.Request.Body.As<JObject>(preserveContent: true))" />
           
           <!-- Extraer parámetros específicos de completions -->
           <set-variable name="temperature" value="@{
               var body = (JObject)context.Variables[&quot;requestBody&quot;];
               return body[&quot;temperature&quot;]?.Value<float>()?? 0.7f;
           }" />
           
           <set-variable name="max-tokens" value="@{
               var body = (JObject)context.Variables[&quot;requestBody&quot;];
               return body[&quot;max_tokens&quot;]?.Value<int>() ?? 800;
           }" />
           
           <set-variable name="model" value="@{
               var body = (JObject)context.Variables[&quot;requestBody&quot;];
               return body[&quot;model&quot;]?.ToString() ?? &quot;gpt-4&quot;;
           }" />
           
           <!-- Determinar el grupo de temperatura -->
           <set-variable name="temperature-group" value="@{
               var temp = (float)context.Variables[&quot;temperature&quot;];
               if (temp <= 0.2) { return &quot;deterministic&quot;; }
               else if (temp <= 0.5) { return &quot;low&quot;; }
               else if (temp <= 0.8) { return &quot;medium&quot;; }
               else { return &quot;high&quot;; }
           }" />
           
           <!-- Caché Semántico Optimizado con Azure Managed Redis -->
           <azure-openai-semantic-cache-lookup 
               score-threshold="0.10" 
               embeddings-backend-id="text-embedding-3-large" 
               embeddings-backend-auth="system-assigned" 
               max-message-count="20" 
               ignore-system-messages="false">
               
               <!-- Particionamiento por suscripción -->
               <vary-by>@(context.Subscription?.Id ?? "public")</vary-by>
               
               <!-- Particionamiento por modelo -->
               <vary-by>@(context.Variables.GetValueOrDefault("model", "gpt-4"))</vary-by>
               
               <!-- Particionamiento por grupo de temperatura -->
               <vary-by>@(context.Variables.GetValueOrDefault("temperature-group", "medium"))</vary-by>
               
               <!-- Particionamiento por rango de tokens -->
               <vary-by>@{
                   var maxTokens = (int)context.Variables["max-tokens"];
                   if (maxTokens <= 256) { return "tokens-small"; }
                   else if (maxTokens <= 1024) { return "tokens-medium"; }
                   else if (maxTokens <= 2048) { return "tokens-large"; }
                   else { return "tokens-xlarge"; }
               }</vary-by>
           </azure-openai-semantic-cache-lookup>
           
           <!-- Headers de debugging -->
           <set-header name="X-Temperature-Group" exists-action="override">
               <value>@(context.Variables.GetValueOrDefault("temperature-group", "medium"))</value>
           </set-header>
           
           <set-header name="X-Model" exists-action="override">
               <value>@(context.Variables.GetValueOrDefault("model", "gpt-4"))</value>
           </set-header>
       </inbound>
       
       <backend>
           <base />
       </backend>
       
       <outbound>
           <base />
           
           <!-- Almacenar respuestas exitosas con TTL de 2 horas en Azure Managed Redis -->
           <choose>
               <when condition="@(context.Response.StatusCode == 200)">
                   <azure-openai-semantic-cache-store duration="7200" />
               </when>
           </choose>
           
           <!-- Headers de monitoreo -->
           <set-header name="X-Semantic-Cache-Status" exists-action="override">
               <value>@{
                   var status = context.Variables.GetValueOrDefault("semantic-cache-lookup-status", "none");
                   return status.ToString().ToUpper();
               }</value>
           </set-header>
           
           <set-header name="X-Semantic-Cache-Score" exists-action="override">
               <value>@{
                   var status = context.Variables.GetValueOrDefault("semantic-cache-lookup-status", "none");
                   if (status.ToString().ToLower() == "hit") {
                       var score = context.Variables.GetValueOrDefault("semantic-cache-lookup-score", "0");
                       return score.ToString();
                   }
                   return "N/A";
               }</value>
           </set-header>
           
           <set-header name="X-Cache-TTL-Hours" exists-action="override">
               <value>2</value>
           </set-header>
           
           <set-header name="X-Response-Time-Ms" exists-action="override">
               <value>@(context.Elapsed.TotalMilliseconds.ToString("F0"))</value>
           </set-header>
           
           <set-header name="X-Cache-Backend" exists-action="override">
               <value>Azure-Managed-Redis</value>
           </set-header>
       </outbound>
       
       <on-error>
           <base />
           
           <set-header name="X-Error-Message" exists-action="override">
               <value>@(context.LastError?.Message ?? "Unknown error")</value>
           </set-header>
           
           <set-header name="X-Error-Model" exists-action="override">
               <value>@(context.Variables.GetValueOrDefault("model", "unknown"))</value>
           </set-header>
       </on-error>
   </policies>
   ```

4. **Guardar la política**

### Paso 4: Aplicar Política de Embeddings

1. **Navegar a la operación de embeddings**:
   ```
   APIs → AOAI → All operations → 
   "Return the embedding vectors for given text prompts" → Inbound processing
   ```

2. **Reemplazar con la política de embeddings**:
   ```xml
   <policies>
       <inbound>
           <base />
           
           <!-- Parsear el cuerpo JSON -->
           <set-variable name="requestBody" value="@(context.Request.Body.As<JObject>(preserveContent:true))" />
           
           <!-- Modelo solicitado -->
           <set-variable name="model" value="@{
               var body = (JObject)context.Variables["requestBody"];
               return (string)(body["model"] ?? "text-embedding-3-large");
           }" />
           
           <!-- Deployment real -->
           <set-variable name="deployment-id" value="@{
               var m = (string)context.Variables["model"];
               if (m == "text-embedding-3-small") { return "text-embedding-3-small"; }
               if (m == "text-embedding-3-large") { return "text-embedding-3-large"; }
               if (m == "text-embedding-ada-002") { return "text-embedding-3-large"; }
               return m;
           }" />
           
           <!-- Tipo de input -->
           <set-variable name="input-type" value="@{
               var body = (JObject)context.Variables["requestBody"];
               return (string)(body["input_type"] ?? "query");
           }" />
           
           <!-- Dimensiones -->
           <set-variable name="dimensions" value="@{
               var body = (JObject)context.Variables["requestBody"];
               var dims = (string)body["dimensions"];
               if (dims == null) {
                   dims = ((string)context.Variables["model"] == "text-embedding-3-large") ? "3072" : "1536";
               }
               return dims;
           }" />
           
           <!-- TTL adaptativo para Azure Managed Redis -->
           <set-variable name="cache-ttl" value="@{
               var t = (string)context.Variables["input-type"];
               if (t == "query") { return 3600; }        // 1 hora
               if (t == "document") { return 604800; }   // 7 días
               if (t == "passage") { return 259200; }    // 3 días
               return 86400;                             // 24 horas default
           }" />
           
           <!-- ¿Es batch? -->
           <set-variable name="is-batch" value="@{
               var input = ((JObject)context.Variables["requestBody"])["input"];
               return input != null && input.Type == JTokenType.Array;
           }" />
           
           <!-- Tamaño del batch -->
           <set-variable name="batch-size" value="@{
               var arr = ((JObject)context.Variables["requestBody"])["input"] as JArray;
               return arr != null ? arr.Count : 1;
           }" />
           
           <!-- Generar clave de caché optimizada para Azure Managed Redis -->
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

               return "emb:v3:" + dep + ":" + mdl + ":" + typ + ":" + dim + ":" + sub + ":" + contentHash + metaHash;
           }" />
           
           <!-- Establecer flag inicial de cache status -->
           <set-variable name="cache-status" value="MISS" />
           
           <!-- Búsqueda en caché de Azure Managed Redis -->
           <cache-lookup-value key="@((string)context.Variables["cache-key"])" variable-name="cached-response" />
           
           <!-- Si hay HIT, devolver inmediatamente -->
           <choose>
               <when condition="@(context.Variables.ContainsKey("cached-response") && context.Variables["cached-response"] != null)">
                   <set-variable name="cache-status" value="HIT" />
                   <return-response>
                       <set-status code="200" reason="OK" />
                       <set-header name="Content-Type" exists-action="override">
                           <value>application/json</value>
                       </set-header>
                       <set-header name="X-Cache-Status" exists-action="override">
                           <value>HIT</value>
                       </set-header>
                       <set-header name="X-Model-Version" exists-action="override">
                           <value>@((string)context.Variables["model"])</value>
                       </set-header>
                       <set-header name="X-Deployment-Used" exists-action="override">
                           <value>@((string)context.Variables["deployment-id"])</value>
                       </set-header>
                       <set-header name="X-Batch-Size" exists-action="override">
                           <value>@(((int)context.Variables["batch-size"]).ToString())</value>
                       </set-header>
                       <set-header name="X-Cache-Key" exists-action="override">
                           <value>@((string)context.Variables["cache-key"])</value>
                       </set-header>
                       <set-header name="X-Cache-Backend" exists-action="override">
                           <value>Azure-Managed-Redis</value>
                       </set-header>
                       <set-body>@((string)context.Variables["cached-response"])</set-body>
                   </return-response>
               </when>
           </choose>
           
           <!-- Rate limiting dinámico -->
           <rate-limit-by-key 
               calls="@(((bool)context.Variables["is-batch"]) ? 100 : 1000)" 
               renewal-period="60" 
               counter-key="@(context.Subscription?.Id ?? context.Request.IpAddress)" />
           
           <!-- Identificador de solicitud -->
           <set-header name="X-Request-ID" exists-action="override">
               <value>@(Guid.NewGuid().ToString())</value>
           </set-header>
       </inbound>
       
       <backend>
           <retry count="3" interval="2" max-interval="10" delta="2" condition="@(context.Response.StatusCode >= 500)">
               <forward-request buffer-request-body="true" timeout="30" />
           </retry>
       </backend>
       
       <outbound>
           <base />
           
           <!-- Almacenar solo respuestas 200 en Azure Managed Redis -->
           <choose>
               <when condition="@(context.Response.StatusCode == 200)">
                   <set-variable name="response-body" value="@(context.Response.Body.As<string>(preserveContent:true))" />
                   <cache-store-value 
                       key="@((string)context.Variables["cache-key"])" 
                       value="@((string)context.Variables["response-body"])" 
                       duration="@((int)context.Variables["cache-ttl"])" />
               </when>
           </choose>
           
           <!-- Headers de diagnóstico -->
           <set-header name="X-Cache-Status" exists-action="override">
               <value>@((string)context.Variables["cache-status"])</value>
           </set-header>
           
           <set-header name="X-Model-Version" exists-action="override">
               <value>@((string)context.Variables["model"])</value>
           </set-header>
           
           <set-header name="X-Deployment-Used" exists-action="override">
               <value>@((string)context.Variables["deployment-id"])</value>
           </set-header>
           
           <set-header name="X-Batch-Size" exists-action="override">
               <value>@(((int)context.Variables["batch-size"]).ToString())</value>
           </set-header>
           
           <set-header name="X-Processing-Time-Ms" exists-action="override">
               <value>@(((int)context.Elapsed.TotalMilliseconds).ToString())</value>
           </set-header>
           
           <set-header name="X-Cache-Key" exists-action="override">
               <value>@((string)context.Variables["cache-key"])</value>
           </set-header>
           
           <set-header name="X-Cache-TTL" exists-action="override">
               <value>@(((int)context.Variables["cache-ttl"]).ToString())</value>
           </set-header>
           
           <set-header name="X-Cache-Backend" exists-action="override">
               <value>Azure-Managed-Redis</value>
           </set-header>
       </outbound>
       
       <on-error>
           <base />
           
           <return-response>
               <set-status code="@(context.Response?.StatusCode ?? 500)" reason="@(context.Response?.StatusReason ?? "Internal Server Error")" />
               <set-header name="Content-Type" exists-action="override">
                   <value>application/json</value>
               </set-header>
               <set-body>@{
                   var err = new JObject(
                       new JProperty("error", new JObject(
                           new JProperty("code",    context.LastError?.Source  ?? "EMBEDDING_ERROR"),
                           new JProperty("message", context.LastError?.Message ?? "An unexpected error occurred"),
                           new JProperty("details", new JObject(
                               new JProperty("requestId", context.RequestId),
                               new JProperty("timestamp", DateTime.UtcNow.ToString("o")),
                               new JProperty("cacheBackend", "Azure-Managed-Redis")
                           ))
                       ))
                   );
                   return err.ToString();
               }</set-body>
           </return-response>
       </on-error>
   </policies>
   ```

3. **Guardar la política**

## ⚙️ Configuración de Azure Managed Redis

### Acceso y Configuración

#### **Opción 1: RedisInsight (Recomendado)**
RedisInsight es una herramienta gráfica open-source para gestionar Azure Managed Redis.

**Instalación y conexión**:
1. Descargar desde: https://redis.io/insight/
2. Configurar conexión:
   - **Host**: `tu-redis-cache.redis.cache.windows.net`
   - **Port**: `6380` (con SSL) o `6379` (sin SSL)
   - **Password**: `[Tu access key de Azure Portal]`
   - **TLS**: Habilitado (recomendado)

#### **Opción 2: Redis-CLI desde línea de comandos**

1. **Instalar redis-cli en Ubuntu/Cloud Shell**:
   ```bash
   sudo apt-get update
   sudo apt-get install redis-tools
   ```

2. **Conectarse a Azure Managed Redis con TLS**:
   ```bash
   redis-cli -p 6380 -h tu-redis-cache.redis.cache.windows.net -a TU_ACCESS_KEY --tls
   ```

### Comandos de Verificación y Optimización

```redis
# Probar conexión
PING
# Respuesta esperada: PONG

# Ver información del servidor y memoria
INFO server
INFO memory
INFO clients

# Test de funcionalidad para APIM Cache
SET "test:apim:completion:1" '{"model":"gpt-4","response":"Hello World"}' EX 7200
SET "test:apim:embedding:1" '{"model":"text-embedding-3-large","vector":[0.1,0.2,0.3]}' EX 604800

# Verificar almacenamiento
GET "test:apim:completion:1"
GET "test:apim:embedding:1"

# Verificar TTL (Time To Live)
TTL "test:apim:completion:1"    # ~7200 segundos (2 horas)
TTL "test:apim:embedding:1"     # ~604800 segundos (7 días)

# Ver todas las claves de test
KEYS "test:apim:*"

# Configurar notificaciones de eventos para APIM
CONFIG SET notify-keyspace-events Ex

# Limpiar datos de test
DEL "test:apim:completion:1" "test:apim:embedding:1"
```

### Configuración Avanzada desde Azure Portal

1. **En Azure Portal → Redis Cache → Advanced settings**:
   - `maxmemory-policy`: `allkeys-lru` (recomendado para caché)
   - `timeout`: `300` (5 minutos)
   - `tcp-keepalive`: `60`

2. **Configurar Named Values en APIM**:
   ```
   API Management → Named values → + Add
   ├── Name: redis-endpoint
   ├── Value: tu-redis-cache.redis.cache.windows.net:6380
   ├── Secret: No
   └── Save
   ```

## 🧪 Validación y Testing

### Test de Política de Completions

```python
import requests
import time

# Configuración
apim_endpoint = "https://apim0-m5gd7y67cu5b6.azure-api.net/aoai/models"
subscription_key = "tu-subscription-key"

headers = {
    "Ocp-Apim-Subscription-Key": subscription_key,
    "Content-Type": "application/json"
}

# Test 1: Consulta inicial (debe ser MISS)
payload1 = {
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "What are Python best practices?"}],
    "temperature": 0.1,
    "max_tokens": 150
}

response1 = requests.post(f"{apim_endpoint}/chat/completions", 
                         json=payload1, headers=headers)

print(f"Test 1 - Cache Status: {response1.headers.get('X-Semantic-Cache-Status')}")
print(f"Temperature Group: {response1.headers.get('X-Temperature-Group')}")
print(f"Model: {response1.headers.get('X-Model')}")
print(f"Cache Backend: {response1.headers.get('X-Cache-Backend')}")

# Test 2: Consulta similar (debe ser HIT con threshold 0.10)
payload2 = {
    "model": "gpt-4", 
    "messages": [{"role": "user", "content": "What are the Python best practices?"}],
    "temperature": 0.1,
    "max_tokens": 150
}

time.sleep(1)  # Esperar propagación de caché

response2 = requests.post(f"{apim_endpoint}/chat/completions", 
                         json=payload2, headers=headers)

print(f"Test 2 - Cache Status: {response2.headers.get('X-Semantic-Cache-Status')}")
print(f"Cache Score: {response2.headers.get('X-Semantic-Cache-Score')}")
print(f"Response Time: {response2.headers.get('X-Response-Time-Ms')}ms")
```

### Test de Política de Embeddings

```python
# Test 1: Embedding inicial (debe ser MISS)
payload1 = {
    "model": "text-embedding-3-large",
    "input": "Azure API Management best practices",
    "input_type": "document",
    "dimensions": 3072
}

response1 = requests.post(f"{apim_endpoint}/embeddings", 
                         json=payload1, headers=headers)

print(f"Test 1 - Cache Status: {response1.headers.get('X-Cache-Status')}")
print(f"Model Version: {response1.headers.get('X-Model-Version')}")
print(f"Deployment Used: {response1.headers.get('X-Deployment-Used')}")
print(f"Cache TTL: {response1.headers.get('X-Cache-TTL')} seconds")
print(f"Processing Time: {response1.headers.get('X-Processing-Time-Ms')}ms")
print(f"Cache Backend: {response1.headers.get('X-Cache-Backend')}")

# Test 2: Embedding idéntico (debe ser HIT)
time.sleep(1)

response2 = requests.post(f"{apim_endpoint}/embeddings", 
                         json=payload1, headers=headers)

print(f"Test 2 - Cache Status: {response2.headers.get('X-Cache-Status')}")
print(f"Cache Key: {response2.headers.get('X-Cache-Key')}")

# Test 3: Batch embedding (validar rate limiting)
payload3 = {
    "model": "text-embedding-3-large",
    "input": [
        "Azure API Management",
        "Semantic caching strategies", 
        "OpenAI embeddings optimization"
    ],
    "input_type": "query",
    "dimensions": 1536
}

response3 = requests.post(f"{apim_endpoint}/embeddings", 
                         json=payload3, headers=headers)

print(f"Test 3 - Batch Size: {response3.headers.get('X-Batch-Size')}")
print(f"Cache Status: {response3.headers.get('X-Cache-Status')}")
```

## 📊 Monitoreo y Métricas

### Dashboard de Application Insights

```kusto
// Hit Rate por Hora - Completions
customMetrics
| where name == "SemanticCacheHitRate"
| where customDimensions.operation == "completions"
| where customDimensions.backend == "Azure-Managed-Redis"
| summarize avg(value) by bin(timestamp, 1h)
| render timechart

// TTL Efectivo - Embeddings  
customMetrics
| where name == "CacheTTL"
| where customDimensions.operation == "embeddings"
| where customDimensions.backend == "Azure-Managed-Redis"
| summarize avg(value) by tostring(customDimensions.input_type)
| render barchart

// Performance de Azure Managed Redis
customMetrics
| where name == "ResponseTime"
| where customDimensions.cacheBackend == "Azure-Managed-Redis"
| summarize avg(value), percentile(value, 95) by bin(timestamp, 5m)
| render timechart
```

### Métricas Específicas de Azure Managed Redis

1. **En Azure Portal → Redis Cache → Monitoring**:
   - **Cache Hits**: Ratio de aciertos de caché
   - **Cache Misses**: Ratio de fallos de caché  
   - **Connected Clients**: Clientes conectados
   - **CPU**: Uso de CPU del Redis
   - **Memory Usage**: Uso de memoria
   - **Network In/Out**: Tráfico de red

2. **Alertas recomendadas**:
   ```
   - Cache Hit Rate < 80% → Revisar políticas de caché
   - Memory Usage > 90% → Escalar o ajustar TTL
   - Connected Clients > 80% → Revisar conexiones
   - CPU > 85% → Considerar escalado vertical
   ```

## 🎯 Mejores Prácticas

### Para Completions con Azure Managed Redis

```python
# Optimizar temperatura para mejor hit rate
request = {
    "messages": [...],
    "temperature": 0.1,  # Baja para consistencia
    "seed": 42,         # Reproducibilidad
    "max_tokens": 150   # Limitar variabilidad
}
```

### Para Embeddings con Azure Managed Redis

```python
# Normalizar texto para maximizar hits
text = text.lower().strip()
text = ' '.join(text.split())  # Normalizar espacios

# Especificar input_type para TTL óptimo
request = {
    "input": text,
    "input_type": "document",  # TTL 7 días vs "query" 1 hora
    "dimensions": 3072
}
```

### Optimización de Azure Managed Redis

1. **Configuración de memoria**:
   ```redis
   # En Azure Portal Advanced settings
   maxmemory-policy: allkeys-lru
   ```

2. **Monitoreo proactivo**:
   - Configurar alertas de memoria > 80%
   - Revisar hit rate semanalmente
   - Monitorear latencia P95 < 10ms

3. **Escalado inteligente**:
   - Usar Standard C3 o superior para producción
   - Considerar Premium para alta disponibilidad
   - Habilitar clustering para cargas altas

### Estimación de Ahorros con Azure Managed Redis

| Métrica | Sin Caché | Con Azure Managed Redis | Ahorro |
|---------|-----------|-------------------------|---------|
| **Completions/día** | 1,000 × $0.03 = $30 | 600 × $0.03 = $18 | $12 (40%) |
| **Embeddings/día** | 10,000 × $0.0004 = $4 | 1,000 × $0.0004 = $0.40 | $3.60 (90%) |
| **Total Mensual** | $1,020 | $552 | **$468 (46%)** |
| **Latencia P95** | 2,000ms | 150ms | **92% mejora** |
| **Costo Redis** | $0 | $85/mes | $85 |
| **Ahorro Neto** | - | - | **$383 (38%)** |

## 🔧 Troubleshooting

### Problemas Comunes con Azure Managed Redis

1. **Hit Rate Bajo en Completions**:
   - Verificar threshold (0.10 recomendado)
   - Revisar particionamiento por temperatura
   - Validar consistencia en system messages

2. **Embeddings no se cachean**:
   - Verificar generación de cache-key
   - Confirmar TTL por input_type
   - Revisar normalización de texto

3. **Conexión a Redis falla**:
   - Verificar firewall rules en Azure Portal
   - Confirmar TLS/SSL habilitado
   - Validar access keys

4. **Performance degradada**:
   - Monitorear CPU y memoria de Redis
   - Revisar número de conexiones concurrentes
   - Considerar escalado vertical

### Logs Útiles

```kusto
// Errores de caché con Azure Managed Redis
requests
| where url contains "aoai/models"
| where resultCode >= 400
| extend cacheBackend = customDimensions.cacheBackend
| where cacheBackend == "Azure-Managed-Redis"
| project timestamp, url, resultCode, customDimensions
| order by timestamp desc

// Performance de caché
customMetrics
| where name in ("CacheHitRate", "ResponseTime")
| where customDimensions.backend == "Azure-Managed-Redis"
| summarize avg(value) by name, bin(timestamp, 1h)
| render timechart
```

## 🚀 Próximos Pasos

1. **Implementar alta disponibilidad** con Redis Premium y geo-replication
2. **Agregar compresión** para respuestas grandes usando Redis compression
3. **Crear SDK cliente** con retry automático y circuit breaker
4. **Implementar cache warming** para consultas frecuentes
5. **Agregar A/B testing** para optimizar thresholds
6. **Integrar con Azure Monitor** para alertas proactivas
7. **Configurar backup automático** para datos críticos de caché

## 📚 Referencias

- [Azure API Management Policies](https://docs.microsoft.com/azure/api-management/api-management-policies)
- [Azure OpenAI Semantic Cache](https://docs.microsoft.com/azure/api-management/azure-openai-semantic-cache-lookup-policy)
- [Azure Managed Redis](https://docs.microsoft.com/azure/azure-cache-for-redis/)
- [RedisInsight Tool](https://redis.io/insight/)
- [Redis CLI Documentation](https://redis.io/docs/connect/cli/)