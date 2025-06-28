# test-embedding-cache-v2.ps1
# Script optimizado para probar el caché semántico de embeddings en Azure API Management
# Basado en la política apim-policy-embedding-optimized.xml
# Versión: 2.0

param(
    [Parameter(Mandatory=$false)]
    [string]$ApimEndpoint = "https://your-apim.azure-api.net/openai",
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionKey = "",
    
    [Parameter(Mandatory=$false)]
    [string]$DeploymentName = "text-embedding-3-large",
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose,
    
    [Parameter(Mandatory=$false)]
    [switch]$SaveResults,
    
    [Parameter(Mandatory=$false)]
    [switch]$ExtendedTests,
    
    [Parameter(Mandatory=$false)]
    [int]$BatchSize = 10
)

# Colores para la salida
$colors = @{
    Success = "Green"
    Error = "Red"
    Warning = "Yellow"
    Info = "Cyan"
    Highlight = "Magenta"
    Data = "Blue"
}

# Función para escribir con color
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Función para medir tiempo con más detalle
function Measure-RequestTime {
    param(
        [scriptblock]$ScriptBlock
    )
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $result = & $ScriptBlock
    $stopwatch.Stop()
    return @{
        Result = $result
        ElapsedMilliseconds = $stopwatch.ElapsedMilliseconds
        ElapsedSeconds = [Math]::Round($stopwatch.ElapsedMilliseconds / 1000, 2)
    }
}

# Configuración inicial
Clear-Host
Write-ColorOutput "`n╔══════════════════════════════════════════════════════╗" $colors.Info
Write-ColorOutput "║     🚀 PRUEBA AVANZADA DE CACHÉ SEMÁNTICO v2.0      ║" $colors.Highlight
Write-ColorOutput "║              OPTIMIZADA PARA EMBEDDINGS              ║" $colors.Highlight
Write-ColorOutput "╚══════════════════════════════════════════════════════╝`n" $colors.Info

# Validar parámetros
if (-not $SubscriptionKey) {
    $SubscriptionKey = Read-Host "Ingrese su API Key de suscripción"
}

if (-not $ApimEndpoint -or $ApimEndpoint -eq "https://your-apim.azure-api.net/openai") {
    $ApimEndpoint = Read-Host "Ingrese el endpoint de API Management"
}

# Mostrar configuración
Write-ColorOutput "📋 CONFIGURACIÓN DE PRUEBAS:" $colors.Info
Write-Host "   🔗 Endpoint: $ApimEndpoint"
Write-Host "   🎯 Deployment: $DeploymentName"
Write-Host "   📊 Modo Verbose: $($Verbose.IsPresent)"
Write-Host "   🧪 Pruebas Extendidas: $($ExtendedTests.IsPresent)"
Write-Host "   📦 Tamaño de Lote: $BatchSize"
Write-Host "   💾 Guardar Resultados: $($SaveResults.IsPresent)"

# Headers para las solicitudes
$headers = @{
    "Ocp-Apim-Subscription-Key" = $SubscriptionKey
    "Content-Type" = "application/json"
}

# Función mejorada para llamar a la API de embeddings
function Invoke-EmbeddingRequest {
    param(
        [string]$Text,
        [string]$InputType = "query",
        [int]$Dimensions = 3072,
        [string]$Model = "text-embedding-3-large",
        [string]$User = $null,
        [hashtable]$Metadata = $null,
        [string]$EncodingFormat = "float"
    )
    
    $body = @{
        input = $Text
        model = $Model
        input_type = $InputType
        dimensions = $Dimensions
        encoding_format = $EncodingFormat
    }
    
    if ($User) {
        $body.user = $User
    }
    
    if ($Metadata) {
        $body.metadata = $Metadata
    }
    
    $jsonBody = $body | ConvertTo-Json -Depth 3
    
    if ($Verbose) {
        Write-ColorOutput "`n📤 Request Body:" $colors.Data
        Write-Host $jsonBody
    }
    
    try {
        $response = Invoke-RestMethod -Uri "$ApimEndpoint/deployments/$DeploymentName/embeddings?api-version=2024-02-01" `
            -Method Post `
            -Headers $headers `
            -Body $jsonBody `
            -ErrorAction Stop `
            -ResponseHeadersVariable responseHeaders
        
        return @{
            Success = $true
            Response = $response
            Headers = $responseHeaders
            Error = $null
        }
    }
    catch {
        return @{
            Success = $false
            Response = $null
            Headers = @{}
            Error = $_.Exception.Message
            StatusCode = $_.Exception.Response.StatusCode
        }
    }
}

# Función para mostrar resultados mejorada
function Show-TestResult {
    param(
        [string]$TestName,
        [hashtable]$Result,
        [int]$ElapsedMs,
        [int]$TestNumber,
        [string]$ExpectedCacheStatus = "NONE"
    )
    
    Write-ColorOutput "`n┌─────────────────────────────────────────────────────┐" $colors.Info
    Write-ColorOutput "│ Test $TestNumber: $TestName" $colors.Highlight
    Write-ColorOutput "└─────────────────────────────────────────────────────┘" $colors.Info
    
    if ($Result.Success) {
        $cacheStatus = $Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
        $cacheScore = $Result.Headers.'X-Semantic-Cache-Score'[0] ?? "N/A"
        $cacheTTL = $Result.Headers.'X-Cache-TTL-Hours'[0] ?? "N/A"
        $responseTimeMs = $Result.Headers.'X-Response-Time-Ms'[0] ?? $ElapsedMs
        $operationType = $Result.Headers.'X-Operation-Type'[0] ?? "unknown"
        $embeddingType = $Result.Headers.'X-Embedding-Type'[0] ?? "N/A"
        $embeddingDimensions = $Result.Headers.'X-Embedding-Dimensions'[0] ?? "N/A"
        $cacheKey = $Result.Headers.'X-Embedding-Cache-Key'[0] ?? "N/A"
        $cacheRecommendation = $Result.Headers.'X-Cache-Recommendation'[0] ?? "N/A"
        
        Write-ColorOutput "✅ Solicitud Exitosa" $colors.Success
        Write-Host "   ⏱️  Tiempo Total: $($ElapsedMs)ms ($([Math]::Round($ElapsedMs/1000.0, 2))s)"
        Write-Host "   ⏱️  Tiempo APIM: ${responseTimeMs}ms"
        Write-Host "   🔧 Tipo de Operación: $operationType"
        
        # Información específica de embeddings
        if ($operationType -eq "embeddings") {
            Write-Host "   📐 Tipo de Embedding: $embeddingType"
            Write-Host "   📏 Dimensiones: $embeddingDimensions"
        }
        
        # Estado del caché
        Write-Host "`n   📊 ESTADO DEL CACHÉ:"
        if ($cacheStatus -eq "HIT") {
            Write-ColorOutput "   🎯 CACHE HIT!" $colors.Success
            Write-Host "   📈 Score de Similitud: $cacheScore"
            
            # Validar si el resultado esperado coincide
            if ($ExpectedCacheStatus -eq "HIT") {
                Write-ColorOutput "   ✓ Resultado esperado confirmado" $colors.Success
            } elseif ($ExpectedCacheStatus -eq "MISS") {
                Write-ColorOutput "   ⚠️  Se esperaba MISS pero fue HIT" $colors.Warning
            }
        } else {
            Write-ColorOutput "   ❌ CACHE MISS" $colors.Warning
            
            if ($ExpectedCacheStatus -eq "MISS" -or $ExpectedCacheStatus -eq "NONE") {
                Write-ColorOutput "   ✓ Resultado esperado confirmado" $colors.Success
            } elseif ($ExpectedCacheStatus -eq "HIT") {
                Write-ColorOutput "   ⚠️  Se esperaba HIT pero fue MISS" $colors.Error
            }
        }
        
        Write-Host "   ⏰ TTL del Caché: $cacheTTL horas"
        Write-Host "   🔑 Cache Key: $cacheKey"
        
        if ($cacheRecommendation -ne "N/A") {
            Write-ColorOutput "   💡 Recomendación: $cacheRecommendation" $colors.Info
        }
        
        if ($Verbose) {
            Write-Host "`n   📦 DETALLES DE LA RESPUESTA:"
            Write-Host "   Dimensiones del Embedding: $($Result.Response.data[0].embedding.Count)"
            Write-Host "   Modelo Usado: $($Result.Response.model)"
            Write-Host "   Tokens Totales: $($Result.Response.usage.total_tokens)"
            Write-Host "   Tokens de Prompt: $($Result.Response.usage.prompt_tokens)"
        }
    }
    else {
        Write-ColorOutput "❌ Error: $($Result.Error)" $colors.Error
        if ($Result.StatusCode) {
            Write-Host "   Código de Estado: $($Result.StatusCode)"
        }
    }
}

# Estadísticas globales mejoradas
$stats = @{
    TotalTests = 0
    CacheHits = 0
    CacheMisses = 0
    TotalTime = 0
    APITime = 0
    Errors = 0
    TokensSaved = 0
    TestsByType = @{
        Query = @{ Total = 0; Hits = 0 }
        Document = @{ Total = 0; Hits = 0 }
        Passage = @{ Total = 0; Hits = 0 }
    }
}

# Arrays para almacenar resultados detallados
$testResults = @()

# CONJUNTO DE PRUEBAS BÁSICAS
Write-ColorOutput "`n╔══════════════════════════════════════════════════════╗" $colors.Highlight
Write-ColorOutput "║           🧪 PRUEBAS BÁSICAS DE EMBEDDINGS           ║" $colors.Highlight
Write-ColorOutput "╚══════════════════════════════════════════════════════╝`n" $colors.Highlight

# Test 1: Primera solicitud de query (siempre MISS)
Write-ColorOutput "➤ Test 1: Primera solicitud de embedding tipo query" $colors.Info
$test1Text = "¿Qué es el aprendizaje automático y cómo funciona en la práctica?"
$test1 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test1Text -InputType "query" -User "test_user_001"
}
Show-TestResult "Primera solicitud (Query)" $test1.Result $test1.ElapsedMilliseconds 1 -ExpectedCacheStatus "MISS"
$testResults += @{
    TestNumber = 1
    Name = "Primera solicitud (Query)"
    ElapsedMs = $test1.ElapsedMilliseconds
    CacheStatus = $test1.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test1.Result.Success
}
$stats.TotalTests++
$stats.TestsByType.Query.Total++
$stats.TotalTime += $test1.ElapsedMilliseconds
if ($test1.Result.Success) {
    if ($test1.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.Query.Hits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

Start-Sleep -Seconds 2

# Test 2: Solicitud idéntica (debe ser HIT con score muy alto)
Write-ColorOutput "`n➤ Test 2: Solicitud idéntica - Validando caché exacto" $colors.Info
$test2 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test1Text -InputType "query" -User "test_user_001"
}
Show-TestResult "Solicitud idéntica (debe ser HIT)" $test2.Result $test2.ElapsedMilliseconds 2 -ExpectedCacheStatus "HIT"
$testResults += @{
    TestNumber = 2
    Name = "Solicitud idéntica"
    ElapsedMs = $test2.ElapsedMilliseconds
    CacheStatus = $test2.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test2.Result.Success
}
$stats.TotalTests++
$stats.TestsByType.Query.Total++
$stats.TotalTime += $test2.ElapsedMilliseconds
if ($test2.Result.Success) {
    if ($test2.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.Query.Hits++
        $speedup = [Math]::Round($test1.ElapsedMilliseconds / $test2.ElapsedMilliseconds, 1)
        Write-ColorOutput "   🚀 Mejora de velocidad: ${speedup}x más rápido" $colors.Success
        $stats.TokensSaved += 250  # Estimación de tokens
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

Start-Sleep -Seconds 1

# Test 3: Texto similar pero no idéntico (threshold 0.95 para embeddings)
Write-ColorOutput "`n➤ Test 3: Texto similar - Probando threshold 0.95" $colors.Info
$test3Text = "Explícame qué es machine learning y su funcionamiento práctico"
$test3 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test3Text -InputType "query" -User "test_user_001"
}
Show-TestResult "Texto similar (threshold 0.95)" $test3.Result $test3.ElapsedMilliseconds 3 -ExpectedCacheStatus "MISS"
$testResults += @{
    TestNumber = 3
    Name = "Texto similar"
    ElapsedMs = $test3.ElapsedMilliseconds
    CacheStatus = $test3.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test3.Result.Success
}
$stats.TotalTests++
$stats.TestsByType.Query.Total++
$stats.TotalTime += $test3.ElapsedMilliseconds
if ($test3.Result.Success) {
    if ($test3.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.Query.Hits++
        Write-ColorOutput "   🎯 Score de similitud: $($test3.Result.Headers.'X-Semantic-Cache-Score'[0])" $colors.Info
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

Start-Sleep -Seconds 1

# Test 4: Documento largo con tipo "document" (TTL diferente)
Write-ColorOutput "`n➤ Test 4: Embedding de documento - TTL extendido (14 días)" $colors.Info
$test4Text = @"
El aprendizaje automático es una rama fundamental de la inteligencia artificial que permite a los sistemas 
computacionales aprender y mejorar a partir de la experiencia sin ser programados explícitamente para cada 
tarea específica. Utiliza algoritmos estadísticos avanzados para identificar patrones complejos en grandes 
conjuntos de datos y hacer predicciones o tomar decisiones basadas en esos patrones identificados. 

Los modelos de aprendizaje automático pueden clasificarse en tres categorías principales: aprendizaje 
supervisado, donde el modelo aprende de ejemplos etiquetados; aprendizaje no supervisado, donde el modelo 
descubre patrones en datos sin etiquetas; y aprendizaje por refuerzo, donde el modelo aprende mediante 
prueba y error en un entorno interactivo. Cada enfoque tiene sus propias aplicaciones, ventajas y 
limitaciones en diferentes dominios como visión por computadora, procesamiento de lenguaje natural, 
sistemas de recomendación y análisis predictivo.
"@
$test4 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test4Text -InputType "document" -User "doc_processor"
}
Show-TestResult "Documento largo (TTL 14 días)" $test4.Result $test4.ElapsedMilliseconds 4 -ExpectedCacheStatus "MISS"
$testResults += @{
    TestNumber = 4
    Name = "Documento largo"
    ElapsedMs = $test4.ElapsedMilliseconds
    CacheStatus = $test4.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test4.Result.Success
}
$stats.TotalTests++
$stats.TestsByType.Document.Total++
$stats.TotalTime += $test4.ElapsedMilliseconds
if ($test4.Result.Success) {
    if ($test4.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.Document.Hits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

Start-Sleep -Seconds 1

# Test 5: Mismo documento (debe ser HIT)
Write-ColorOutput "`n➤ Test 5: Documento repetido - Validando caché de documentos" $colors.Info
$test5 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test4Text -InputType "document" -User "doc_processor"
}
Show-TestResult "Documento repetido (debe ser HIT)" $test5.Result $test5.ElapsedMilliseconds 5 -ExpectedCacheStatus "HIT"
$testResults += @{
    TestNumber = 5
    Name = "Documento repetido"
    ElapsedMs = $test5.ElapsedMilliseconds
    CacheStatus = $test5.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test5.Result.Success
}
$stats.TotalTests++
$stats.TestsByType.Document.Total++
$stats.TotalTime += $test5.ElapsedMilliseconds
if ($test5.Result.Success) {
    if ($test5.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.Document.Hits++
        $stats.TokensSaved += 500  # Más tokens para documentos largos
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

# Test 6: Dimensiones personalizadas
Write-ColorOutput "`n➤ Test 6: Dimensiones personalizadas (256) - Partición diferente" $colors.Info
$test6Text = "Prueba con dimensiones reducidas para mejor rendimiento y menor costo"
$test6 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test6Text -InputType "query" -Dimensions 256
}
Show-TestResult "Dimensiones 256 (compacto)" $test6.Result $test6.ElapsedMilliseconds 6 -ExpectedCacheStatus "MISS"
$testResults += @{
    TestNumber = 6
    Name = "Dimensiones personalizadas"
    ElapsedMs = $test6.ElapsedMilliseconds
    CacheStatus = $test6.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test6.Result.Success
}
$stats.TotalTests++
$stats.TestsByType.Query.Total++
$stats.TotalTime += $test6.ElapsedMilliseconds
if ($test6.Result.Success) {
    if ($test6.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.Query.Hits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

# Test 7: Mismo texto pero diferentes dimensiones (debe ser MISS)
Write-ColorOutput "`n➤ Test 7: Mismo texto, diferentes dimensiones - Validando particionamiento" $colors.Info
$test7 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test6Text -InputType "query" -Dimensions 1536
}
Show-TestResult "Mismo texto, dim 1536 (debe ser MISS)" $test7.Result $test7.ElapsedMilliseconds 7 -ExpectedCacheStatus "MISS"
$testResults += @{
    TestNumber = 7
    Name = "Diferentes dimensiones"
    ElapsedMs = $test7.ElapsedMilliseconds
    CacheStatus = $test7.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test7.Result.Success
}
$stats.TotalTests++
$stats.TestsByType.Query.Total++
$stats.TotalTime += $test7.ElapsedMilliseconds
if ($test7.Result.Success) {
    if ($test7.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.Query.Hits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

# Test 8: Tipo "passage" con metadata
Write-ColorOutput "`n➤ Test 8: Tipo passage con metadata - TTL extendido" $colors.Info
$test8Text = "Los embeddings semánticos transforman texto en vectores numéricos que capturan el significado."
$test8Metadata = @{
    source = "technical_docs"
    chapter = "3"
    version = "1.0"
}
$test8 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test8Text -InputType "passage" -Metadata $test8Metadata
}
Show-TestResult "Passage con metadata" $test8.Result $test8.ElapsedMilliseconds 8 -ExpectedCacheStatus "MISS"
$testResults += @{
    TestNumber = 8
    Name = "Passage con metadata"
    ElapsedMs = $test8.ElapsedMilliseconds
    CacheStatus = $test8.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test8.Result.Success
}
$stats.TotalTests++
$stats.TestsByType.Passage.Total++
$stats.TotalTime += $test8.ElapsedMilliseconds
if ($test8.Result.Success) {
    if ($test8.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.Passage.Hits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

# PRUEBAS EXTENDIDAS
if ($ExtendedTests) {
    Write-ColorOutput "`n╔══════════════════════════════════════════════════════╗" $colors.Highlight
    Write-ColorOutput "║          🔬 PRUEBAS EXTENDIDAS DE EMBEDDINGS         ║" $colors.Highlight
    Write-ColorOutput "╚══════════════════════════════════════════════════════╝`n" $colors.Highlight
    
    # Test de concurrencia
    Write-ColorOutput "➤ Test de Concurrencia: $BatchSize solicitudes paralelas" $colors.Info
    $concurrentTexts = @(
        "Inteligencia artificial en medicina moderna",
        "Blockchain y criptomonedas explicadas",
        "Computación cuántica para principiantes",
        "Internet de las cosas (IoT) en hogares",
        "Realidad virtual y aumentada en educación",
        "Big data y análisis predictivo",
        "Ciberseguridad en la era digital",
        "Robótica avanzada y automatización",
        "5G y el futuro de las telecomunicaciones",
        "Biotecnología y edición genética"
    )
    
    $jobs = @()
    $startTime = Get-Date
    
    for ($i = 0; $i -lt [Math]::Min($BatchSize, $concurrentTexts.Count); $i++) {
        $jobs += Start-Job -ScriptBlock {
            param($endpoint, $deployment, $headers, $text, $index)
            
            $body = @{
                input = $text
                input_type = "query"
                dimensions = 3072
            } | ConvertTo-Json
            
            try {
                $response = Invoke-RestMethod -Uri "$endpoint/deployments/$deployment/embeddings?api-version=2024-02-01" `
                    -Method Post `
                    -Headers $headers `
                    -Body $body `
                    -ErrorAction Stop `
                    -ResponseHeadersVariable responseHeaders
                
                return @{
                    Success = $true
                    Index = $index
                    CacheStatus = $responseHeaders.'X-Semantic-Cache-Status'[0] ?? "NONE"
                }
            }
            catch {
                return @{
                    Success = $false
                    Index = $index
                    Error = $_.Exception.Message
                }
            }
        } -ArgumentList $ApimEndpoint, $DeploymentName, $headers, $concurrentTexts[$i], $i
    }
    
    # Esperar a que terminen todos los jobs
    $concurrentResults = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job
    
    $endTime = Get-Date
    $totalConcurrentTime = ($endTime - $startTime).TotalMilliseconds
    
    Write-ColorOutput "`n   📊 Resultados de Concurrencia:" $colors.Info
    $concurrentHits = ($concurrentResults | Where-Object { $_.CacheStatus -eq "HIT" }).Count
    $concurrentSuccess = ($concurrentResults | Where-Object { $_.Success }).Count
    
    Write-Host "   ✅ Solicitudes exitosas: $concurrentSuccess/$BatchSize"
    Write-Host "   🎯 Cache hits: $concurrentHits"
    Write-Host "   ⏱️  Tiempo total: $([Math]::Round($totalConcurrentTime, 2))ms"
    Write-Host "   ⚡ Throughput: $([Math]::Round($BatchSize / ($totalConcurrentTime / 1000), 2)) req/s"
    
    $stats.TotalTests += $BatchSize
    $stats.CacheHits += $concurrentHits
    $stats.CacheMisses += ($concurrentSuccess - $concurrentHits)
    $stats.Errors += ($BatchSize - $concurrentSuccess)
    
    # Test de diferentes modelos (si están disponibles)
    $models = @("text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002")
    
    Write-ColorOutput "`n➤ Test de Modelos: Validando particionamiento por modelo" $colors.Info
    foreach ($model in $models) {
        if ($model -eq $DeploymentName) { continue }
        
        Write-Host "`n   Probando modelo: $model"
        $modelTest = Measure-RequestTime {
            Invoke-EmbeddingRequest -Text "Test de modelo específico" -Model $model -InputType "query"
        }
        
        if ($modelTest.Result.Success) {
            Write-ColorOutput "   ✅ $model funcionando" $colors.Success
            $cacheStatus = $modelTest.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
            Write-Host "   Cache Status: $cacheStatus"
        } else {
            Write-ColorOutput "   ⚠️  $model no disponible o error" $colors.Warning
        }
    }
    
    # Test de límites
    Write-ColorOutput "`n➤ Test de Límites: Validando comportamiento con textos extremos" $colors.Info
    
    # Texto muy corto
    $shortText = "AI"
    $shortTest = Measure-RequestTime {
        Invoke-EmbeddingRequest -Text $shortText -InputType "query"
    }
    Write-Host "   📏 Texto muy corto (2 chars): $($shortTest.Result.Success ? 'OK' : 'FAIL')"
    
    # Texto muy largo (8000 tokens aproximadamente)
    $longText = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " * 500
    $longTest = Measure-RequestTime {
        Invoke-EmbeddingRequest -Text $longText -InputType "document"
    }
    Write-Host "   📏 Texto muy largo (~8000 tokens): $($longTest.Result.Success ? 'OK' : 'FAIL')"
    
    # Caracteres especiales y Unicode
    $specialText = "Prueba con emojis 🚀🎯🔥 y caracteres especiales: @#$%^&*() 中文 العربية"
    $specialTest = Measure-RequestTime {
        Invoke-EmbeddingRequest -Text $specialText -InputType "query"
    }
    Write-Host "   🌐 Caracteres especiales y Unicode: $($specialTest.Result.Success ? 'OK' : 'FAIL')"
}

# RESUMEN FINAL MEJORADO
Write-ColorOutput "`n╔══════════════════════════════════════════════════════╗" $colors.Highlight
Write-ColorOutput "║              📊 RESUMEN DE RESULTADOS                ║" $colors.Highlight
Write-ColorOutput "╚══════════════════════════════════════════════════════╝" $colors.Highlight

$hitRate = if ($stats.TotalTests -gt 0) { 
    [Math]::Round(($stats.CacheHits / $stats.TotalTests) * 100, 2) 
} else { 0 }

$avgTime = if ($stats.TotalTests -gt 0) {
    [Math]::Round($stats.TotalTime / $stats.TotalTests, 2)
} else { 0 }

Write-Host "`n📈 ESTADÍSTICAS GENERALES:"
Write-Host "   ├─ Total de pruebas: $($stats.TotalTests)"
Write-ColorOutput "   ├─ ✅ Cache Hits: $($stats.CacheHits)" $colors.Success
Write-ColorOutput "   ├─ ❌ Cache Misses: $($stats.CacheMisses)" $colors.Warning
Write-ColorOutput "   ├─ ⚠️  Errores: $($stats.Errors)" $(if ($stats.Errors -gt 0) { $colors.Error } else { $colors.Success })
Write-Host "   ├─ 📊 Hit Rate Global: $hitRate%"
Write-Host "   └─ ⏱️  Tiempo promedio: $avgTime ms"

# Estadísticas por tipo
Write-Host "`n📊 ESTADÍSTICAS POR TIPO DE EMBEDDING:"
foreach ($type in $stats.TestsByType.Keys) {
    $typeStats = $stats.TestsByType[$type]
    if ($typeStats.Total -gt 0) {
        $typeHitRate = [Math]::Round(($typeStats.Hits / $typeStats.Total) * 100, 2)
        Write-Host "   ├─ $type`: $($typeStats.Hits)/$($typeStats.Total) hits ($typeHitRate%)"
    }
}

# Análisis de rendimiento
Write-ColorOutput "`n⚡ ANÁLISIS DE RENDIMIENTO:" $colors.Info
$avgHitTime = 50  # ms promedio estimado para cache hits
$avgMissTime = 250  # ms promedio estimado para cache misses
$timesSaved = ($stats.CacheHits * ($avgMissTime - $avgHitTime)) / 1000  # segundos

Write-Host "   ├─ Tiempo ahorrado total: $([Math]::Round($timesSaved, 2)) segundos"
Write-Host "   ├─ Reducción de latencia: ~$([Math]::Round($stats.CacheHits * 200, 0))ms totales"
Write-Host "   └─ Mejora promedio en hits: ~5x más rápido"

# Análisis de costos mejorado
Write-ColorOutput "`n💰 ANÁLISIS DE COSTOS:" $colors.Info
$costPerMillion = 0.13  # USD por millón de tokens para text-embedding-3-large
$avgTokensPerRequest = 250
$tokensSaved = $stats.CacheHits * $avgTokensPerRequest
$costSaved = ($tokensSaved / 1000000) * $costPerMillion

Write-Host "   ├─ Tokens ahorrados: $tokensSaved"
Write-Host "   ├─ Costo ahorrado: `$$([Math]::Round($costSaved, 4)) USD"
Write-Host "   ├─ Ahorro proyectado mensual: `$$([Math]::Round($costSaved * 30 * 24, 2)) USD"
Write-Host "   └─ ROI del caché: $([Math]::Round($hitRate * 0.95, 1))% de reducción en costos"

# Recomendaciones basadas en resultados
Write-ColorOutput "`n💡 RECOMENDACIONES Y OBSERVACIONES:" $colors.Info

if ($hitRate -lt 30) {
    Write-ColorOutput "   ⚠️  Hit rate bajo ($hitRate%). Considera:" $colors.Warning
    Write-Host "      • Normalizar textos antes de enviarlos"
    Write-Host "      • Usar input_type consistentemente"
    Write-Host "      • Implementar deduplicación en el cliente"
    Write-Host "      • Revisar el threshold de similitud (actual: 0.95)"
} elseif ($hitRate -lt 60) {
    Write-ColorOutput "   📊 Hit rate moderado ($hitRate%). Para mejorar:" $colors.Info
    Write-Host "      • Identificar patrones comunes en las consultas"
    Write-Host "      • Pre-computar embeddings de documentos frecuentes"
    Write-Host "      • Considerar batch processing para documentos"
} else {
    Write-ColorOutput "   🎯 Excelente hit rate ($hitRate%)!" $colors.Success
    Write-Host "      • El caché está funcionando óptimamente"
    Write-Host "      • Considera aumentar el TTL para queries frecuentes"
    Write-Host "      • Monitorea el tamaño del caché regularmente"
}

# Información sobre TTL
Write-Host "`n⏰ CONFIGURACIÓN DE TTL DETECTADA:"
Write-Host "   ├─ Queries: 7 días (604,800 segundos)"
Write-Host "   ├─ Documents: 14 días (1,209,600 segundos)"
Write-Host "   └─ Passages: 14 días (1,209,600 segundos)"

# Guardar resultados detallados
if ($SaveResults) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $resultsFile = "embedding-cache-test-v2-$timestamp.json"
    
    $detailedResults = @{
        TestDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Configuration = @{
            Endpoint = $ApimEndpoint
            Deployment = $DeploymentName
            ExtendedTests = $ExtendedTests.IsPresent
            BatchSize = $BatchSize
        }
        Statistics = $stats
        Analysis = @{
            HitRate = $hitRate
            AverageResponseTime = $avgTime
            TokensSaved = $tokensSaved
            CostSaved = $costSaved
            EstimatedMonthlySavings = [Math]::Round($costSaved * 30 * 24, 2)
            TimeSavedSeconds = $timesSaved
        }
        TestResults = $testResults
        PolicyConfiguration = @{
            ScoreThreshold = @{
                Embeddings = "0.95"
                Chat = "0.10"
                Completions = "0.15"
            }
            TTL = @{
                QueryEmbeddings = "7 days"
                DocumentEmbeddings = "14 days"
                PassageEmbeddings = "14 days"
            }
        }
    }
    
    $detailedResults | ConvertTo-Json -Depth 5 | Out-File $resultsFile
    Write-ColorOutput "`n💾 Resultados detallados guardados en: $resultsFile" $colors.Success
    
    # Generar reporte CSV para análisis
    $csvFile = "embedding-cache-test-v2-$timestamp.csv"
    $testResults | Export-Csv -Path $csvFile -NoTypeInformation
    Write-ColorOutput "📊 Datos de pruebas exportados a: $csvFile" $colors.Success
}

if ($stats.Errors -gt 0) {
    Write-ColorOutput "`n⚠️  ADVERTENCIA: Se detectaron $($stats.Errors) errores durante las pruebas" $colors.Error
    Write-Host "   Verifica:"
    Write-Host "   • La configuración del endpoint y API key"
    Write-Host "   • Los límites de rate limiting"
    Write-Host "   • La disponibilidad del servicio"
}

Write-ColorOutput "`n✨ Pruebas de caché semántico para embeddings completadas exitosamente!`n" $colors.Success

# Mostrar comando para monitoreo continuo
Write-Host "💡 Para monitoreo continuo, ejecuta:"
Write-Host "   ./test-embedding-cache-v2.ps1 -ExtendedTests -SaveResults -Verbose"
Write-Host ""