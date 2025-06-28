# Test-EmbeddingCache.ps1
# Script de PowerShell para probar el Caché Semántico de Embeddings en Azure API Management
# Autor: Azure API Management Team
# Versión: 1.0

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
    [switch]$SaveResults
)

# Colores para la salida
$colors = @{
    Success = "Green"
    Error = "Red"
    Warning = "Yellow"
    Info = "Cyan"
    Highlight = "Magenta"
}

# Función para escribir con color
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Función para medir tiempo
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
    }
}

# Configuración inicial
Write-ColorOutput "`n========================================" $colors.Info
Write-ColorOutput "🚀 PRUEBA DE CACHÉ SEMÁNTICO - EMBEDDINGS" $colors.Highlight
Write-ColorOutput "========================================`n" $colors.Info

# Validar parámetros
if (-not $SubscriptionKey) {
    $SubscriptionKey = Read-Host "Ingrese su API Key de suscripción"
}

if (-not $ApimEndpoint -or $ApimEndpoint -eq "https://your-apim.azure-api.net/openai") {
    $ApimEndpoint = Read-Host "Ingrese el endpoint de API Management"
}

# Mostrar configuración
Write-ColorOutput "📋 Configuración:" $colors.Info
Write-Host "   Endpoint: $ApimEndpoint"
Write-Host "   Deployment: $DeploymentName"
Write-Host "   Modo Verbose: $($Verbose.IsPresent)"
Write-Host ""

# Headers para las solicitudes
$headers = @{
    "Ocp-Apim-Subscription-Key" = $SubscriptionKey
    "Content-Type" = "application/json"
}

# Función para llamar a la API de embeddings
function Invoke-EmbeddingRequest {
    param(
        [string]$Text,
        [string]$InputType = "query",
        [int]$Dimensions = 3072,
        [string]$User = $null
    )
    
    $body = @{
        input = $Text
        input_type = $InputType
        dimensions = $Dimensions
    }
    
    if ($User) {
        $body.user = $User
    }
    
    $jsonBody = $body | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "$ApimEndpoint/deployments/$DeploymentName/embeddings" `
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
        }
    }
}

# Función para mostrar resultados de una prueba
function Show-TestResult {
    param(
        [string]$TestName,
        [hashtable]$Result,
        [int]$ElapsedMs,
        [int]$TestNumber
    )
    
    Write-ColorOutput "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" $colors.Info
    Write-ColorOutput "Test $TestNumber: $TestName" $colors.Highlight
    Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" $colors.Info
    
    if ($Result.Success) {
        $cacheStatus = $Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
        $cacheScore = $Result.Headers.'X-Semantic-Cache-Score'[0] ?? "N/A"
        $cacheTTL = $Result.Headers.'X-Cache-TTL-Hours'[0] ?? "N/A"
        $responseTimeMs = $Result.Headers.'X-Response-Time-Ms'[0] ?? $ElapsedMs
        
        Write-ColorOutput "✅ Éxito" $colors.Success
        Write-Host "   ⏱️  Tiempo de respuesta: $($ElapsedMs)ms"
        Write-Host "   📊 Estado del caché: $cacheStatus"
        
        if ($cacheStatus -eq "HIT") {
            Write-ColorOutput "   🎯 CACHE HIT!" $colors.Success
            Write-Host "   📈 Score de similitud: $cacheScore"
        } else {
            Write-ColorOutput "   ❌ CACHE MISS" $colors.Warning
        }
        
        Write-Host "   ⏰ TTL del caché: $cacheTTL horas"
        
        if ($Verbose) {
            Write-Host "`n   Dimensiones del embedding: $($Result.Response.data[0].embedding.Count)"
            Write-Host "   Modelo usado: $($Result.Response.model)"
            Write-Host "   Tokens usados: $($Result.Response.usage.total_tokens)"
        }
    }
    else {
        Write-ColorOutput "❌ Error: $($Result.Error)" $colors.Error
    }
}

# Estadísticas globales
$stats = @{
    TotalTests = 0
    CacheHits = 0
    CacheMisses = 0
    TotalTime = 0
    Errors = 0
}

# CONJUNTO DE PRUEBAS
Write-ColorOutput "`n🧪 INICIANDO PRUEBAS DE EMBEDDINGS`n" $colors.Highlight

# Test 1: Primera solicitud (siempre MISS)
Write-ColorOutput "➤ Ejecutando Test 1: Primera solicitud de embedding" $colors.Info
$test1Text = "¿Qué es el aprendizaje automático y cómo funciona?"
$test1 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test1Text -InputType "query"
}
Show-TestResult "Primera solicitud (Query)" $test1.Result $test1.ElapsedMilliseconds 1
$stats.TotalTests++
$stats.TotalTime += $test1.ElapsedMilliseconds
if ($test1.Result.Success) {
    if ($test1.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

Start-Sleep -Seconds 2

# Test 2: Solicitud idéntica (debería ser HIT)
Write-ColorOutput "`n➤ Ejecutando Test 2: Solicitud idéntica" $colors.Info
$test2 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test1Text -InputType "query"
}
Show-TestResult "Solicitud idéntica (debe ser HIT)" $test2.Result $test2.ElapsedMilliseconds 2
$stats.TotalTests++
$stats.TotalTime += $test2.ElapsedMilliseconds
if ($test2.Result.Success) {
    if ($test2.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        Write-ColorOutput "   💡 Mejora de velocidad: $([Math]::Round($test1.ElapsedMilliseconds / $test2.ElapsedMilliseconds, 1))x" $colors.Success
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

Start-Sleep -Seconds 1

# Test 3: Texto similar pero no idéntico
Write-ColorOutput "`n➤ Ejecutando Test 3: Texto similar" $colors.Info
$test3Text = "Explícame qué es machine learning y su funcionamiento"
$test3 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test3Text -InputType "query"
}
Show-TestResult "Texto similar (threshold 0.95)" $test3.Result $test3.ElapsedMilliseconds 3
$stats.TotalTests++
$stats.TotalTime += $test3.ElapsedMilliseconds
if ($test3.Result.Success) {
    if ($test3.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

Start-Sleep -Seconds 1

# Test 4: Documento largo (diferente TTL)
Write-ColorOutput "`n➤ Ejecutando Test 4: Embedding de documento" $colors.Info
$test4Text = @"
El aprendizaje automático es una rama de la inteligencia artificial que permite a los sistemas 
aprender y mejorar a partir de la experiencia sin ser programados explícitamente. Utiliza 
algoritmos estadísticos para identificar patrones en datos y hacer predicciones o decisiones 
basadas en esos patrones. Los modelos de ML pueden ser supervisados, no supervisados o de 
refuerzo, cada uno con sus propias aplicaciones y ventajas en diferentes dominios.
"@
$test4 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test4Text -InputType "document"
}
Show-TestResult "Documento largo (TTL 14 días)" $test4.Result $test4.ElapsedMilliseconds 4
$stats.TotalTests++
$stats.TotalTime += $test4.ElapsedMilliseconds
if ($test4.Result.Success) {
    if ($test4.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

Start-Sleep -Seconds 1

# Test 5: Mismo documento (debe ser HIT)
Write-ColorOutput "`n➤ Ejecutando Test 5: Mismo documento" $colors.Info
$test5 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test4Text -InputType "document"
}
Show-TestResult "Documento repetido (debe ser HIT)" $test5.Result $test5.ElapsedMilliseconds 5
$stats.TotalTests++
$stats.TotalTime += $test5.ElapsedMilliseconds
if ($test5.Result.Success) {
    if ($test5.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

Start-Sleep -Seconds 1

# Test 6: Dimensiones personalizadas
Write-ColorOutput "`n➤ Ejecutando Test 6: Dimensiones personalizadas" $colors.Info
$test6Text = "Prueba con dimensiones reducidas para mejor rendimiento"
$test6 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test6Text -InputType "query" -Dimensions 256
}
Show-TestResult "Dimensiones 256 (compacto)" $test6.Result $test6.ElapsedMilliseconds 6
$stats.TotalTests++
$stats.TotalTime += $test6.ElapsedMilliseconds
if ($test6.Result.Success) {
    if ($test6.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

# Test 7: Con usuario específico
Write-ColorOutput "`n➤ Ejecutando Test 7: Con usuario específico" $colors.Info
$test7Text = "Embedding con contexto de usuario"
$test7 = Measure-RequestTime {
    Invoke-EmbeddingRequest -Text $test7Text -InputType "query" -User "test_user_123"
}
Show-TestResult "Con usuario (partición de caché)" $test7.Result $test7.ElapsedMilliseconds 7
$stats.TotalTests++
$stats.TotalTime += $test7.ElapsedMilliseconds
if ($test7.Result.Success) {
    if ($test7.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

# RESUMEN FINAL
Write-ColorOutput "`n════════════════════════════════════════" $colors.Highlight
Write-ColorOutput "📊 RESUMEN DE RESULTADOS" $colors.Highlight
Write-ColorOutput "════════════════════════════════════════" $colors.Highlight

$hitRate = if ($stats.TotalTests -gt 0) { 
    [Math]::Round(($stats.CacheHits / $stats.TotalTests) * 100, 2) 
} else { 0 }

$avgTime = if ($stats.TotalTests -gt 0) {
    [Math]::Round($stats.TotalTime / $stats.TotalTests, 2)
} else { 0 }

Write-Host "`n📈 Estadísticas Generales:"
Write-Host "   Total de pruebas: $($stats.TotalTests)"
Write-ColorOutput "   ✅ Cache Hits: $($stats.CacheHits)" $colors.Success
Write-ColorOutput "   ❌ Cache Misses: $($stats.CacheMisses)" $colors.Warning
Write-ColorOutput "   ⚠️  Errores: $($stats.Errors)" $(if ($stats.Errors -gt 0) { $colors.Error } else { $colors.Success })
Write-Host "   📊 Hit Rate: $hitRate%"
Write-Host "   ⏱️  Tiempo promedio: $avgTime ms"

# Análisis de ahorro de costos
Write-ColorOutput "`n💰 Análisis de Costos:" $colors.Info
$tokensPerRequest = 250  # Estimación promedio
$costPer1KTokens = 0.0001  # text-embedding-3-large
$tokensSaved = $stats.CacheHits * $tokensPerRequest
$costSaved = ($tokensSaved / 1000) * $costPer1KTokens

Write-Host "   Tokens ahorrados: $tokensSaved"
Write-Host "   Costo ahorrado: `$$([Math]::Round($costSaved, 4))"
Write-Host "   Reducción de latencia: ~$([Math]::Round($stats.CacheHits * 200, 0))ms totales"

# Guardar resultados si se solicita
if ($SaveResults) {
    $resultsFile = "embedding-cache-test-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $results = @{
        TestDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Configuration = @{
            Endpoint = $ApimEndpoint
            Deployment = $DeploymentName
        }
        Statistics = $stats
        Analysis = @{
            HitRate = $hitRate
            AverageResponseTime = $avgTime
            TokensSaved = $tokensSaved
            CostSaved = $costSaved
        }
    }
    
    $results | ConvertTo-Json -Depth 3 | Out-File $resultsFile
    Write-ColorOutput "`n💾 Resultados guardados en: $resultsFile" $colors.Success
}

Write-ColorOutput "`n✨ Pruebas completadas exitosamente!`n" $colors.Success

# Recomendaciones basadas en resultados
if ($hitRate -lt 50) {
    Write-ColorOutput "⚠️  RECOMENDACIONES:" $colors.Warning
    Write-Host "   - El hit rate es bajo ($hitRate%). Considera:"
    Write-Host "     • Normalizar los textos de entrada"
    Write-Host "     • Usar el mismo input_type consistentemente"
    Write-Host "     • Verificar que las dimensiones coincidan"
}

if ($stats.Errors -gt 0) {
    Write-ColorOutput "`n⚠️  Se detectaron errores. Verifica:" $colors.Error
    Write-Host "   - La configuración del endpoint"
    Write-Host "   - La validez de la API key"
    Write-Host "   - La conectividad de red"
}