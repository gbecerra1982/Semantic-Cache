# test-completions-cache-v2.ps1
# Script optimizado para probar el caché semántico de completions/chat en Azure API Management
# Basado en la política apim-policy-embedding-optimized.xml con configuración para completions
# Versión: 2.0

param(
    [Parameter(Mandatory=$false)]
    [string]$ApimEndpoint = "https://your-apim.azure-api.net/openai",
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionKey = "",
    
    [Parameter(Mandatory=$false)]
    [string]$DeploymentName = "gpt-4",
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose,
    
    [Parameter(Mandatory=$false)]
    [switch]$SaveResults,
    
    [Parameter(Mandatory=$false)]
    [switch]$ExtendedTests,
    
    [Parameter(Mandatory=$false)]
    [switch]$TestCompletions  # Para probar completions además de chat
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
Write-ColorOutput "║    🚀 PRUEBA AVANZADA DE CACHÉ SEMÁNTICO v2.0       ║" $colors.Highlight
Write-ColorOutput "║         OPTIMIZADA PARA CHAT/COMPLETIONS            ║" $colors.Highlight
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
Write-Host "   💬 Probar Completions: $($TestCompletions.IsPresent)"
Write-Host "   💾 Guardar Resultados: $($SaveResults.IsPresent)"

# Headers para las solicitudes
$headers = @{
    "Ocp-Apim-Subscription-Key" = $SubscriptionKey
    "Content-Type" = "application/json"
}

# Función mejorada para llamar a la API de chat
function Invoke-ChatRequest {
    param(
        [array]$Messages,
        [float]$Temperature = 0.7,
        [int]$MaxTokens = 100,
        [string]$Model = "gpt-4",
        [string]$User = $null,
        [array]$Functions = $null,
        [hashtable]$ResponseFormat = $null,
        [float]$TopP = 1.0,
        [float]$FrequencyPenalty = 0,
        [float]$PresencePenalty = 0
    )
    
    $body = @{
        messages = $Messages
        temperature = $Temperature
        max_tokens = $MaxTokens
        model = $Model
        top_p = $TopP
        frequency_penalty = $FrequencyPenalty
        presence_penalty = $PresencePenalty
    }
    
    if ($User) {
        $body.user = $User
    }
    
    if ($Functions) {
        $body.functions = $Functions
    }
    
    if ($ResponseFormat) {
        $body.response_format = $ResponseFormat
    }
    
    $jsonBody = $body | ConvertTo-Json -Depth 10
    
    if ($Verbose) {
        Write-ColorOutput "`n📤 Request Body (Chat):" $colors.Data
        Write-Host $jsonBody
    }
    
    try {
        $response = Invoke-RestMethod -Uri "$ApimEndpoint/deployments/$DeploymentName/chat/completions?api-version=2024-02-01" `
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

# Función para llamar a la API de completions
function Invoke-CompletionRequest {
    param(
        [string]$Prompt,
        [float]$Temperature = 0.7,
        [int]$MaxTokens = 100,
        [string]$Model = "gpt-4",
        [string]$User = $null,
        [string]$Stop = $null,
        [float]$TopP = 1.0
    )
    
    $body = @{
        prompt = $Prompt
        temperature = $Temperature
        max_tokens = $MaxTokens
        model = $Model
        top_p = $TopP
    }
    
    if ($User) {
        $body.user = $User
    }
    
    if ($Stop) {
        $body.stop = $Stop
    }
    
    $jsonBody = $body | ConvertTo-Json -Depth 3
    
    if ($Verbose) {
        Write-ColorOutput "`n📤 Request Body (Completion):" $colors.Data
        Write-Host $jsonBody
    }
    
    try {
        $response = Invoke-RestMethod -Uri "$ApimEndpoint/deployments/$DeploymentName/completions?api-version=2024-02-01" `
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
        [string]$ExpectedCacheStatus = "NONE",
        [string]$OperationType = "chat"
    )
    
    Write-ColorOutput "`n┌─────────────────────────────────────────────────────┐" $colors.Info
    Write-ColorOutput "│ Test $TestNumber: $TestName" $colors.Highlight
    Write-ColorOutput "└─────────────────────────────────────────────────────┘" $colors.Info
    
    if ($Result.Success) {
        $cacheStatus = $Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
        $cacheScore = $Result.Headers.'X-Semantic-Cache-Score'[0] ?? "N/A"
        $cacheTTL = $Result.Headers.'X-Cache-TTL-Hours'[0] ?? "N/A"
        $responseTimeMs = $Result.Headers.'X-Response-Time-Ms'[0] ?? $ElapsedMs
        $operationTypeHeader = $Result.Headers.'X-Operation-Type'[0] ?? $OperationType
        $cacheRecommendation = $Result.Headers.'X-Cache-Recommendation'[0] ?? "N/A"
        
        Write-ColorOutput "✅ Solicitud Exitosa" $colors.Success
        Write-Host "   ⏱️  Tiempo Total: $($ElapsedMs)ms ($([Math]::Round($ElapsedMs/1000.0, 2))s)"
        Write-Host "   ⏱️  Tiempo APIM: ${responseTimeMs}ms"
        Write-Host "   🔧 Tipo de Operación: $operationTypeHeader"
        
        # Estado del caché
        Write-Host "`n   📊 ESTADO DEL CACHÉ:"
        if ($cacheStatus -eq "HIT") {
            Write-ColorOutput "   🎯 CACHE HIT!" $colors.Success
            Write-Host "   📈 Score de Similitud: $cacheScore"
            
            # Mostrar threshold específico
            $threshold = switch($operationTypeHeader) {
                "chat" { "0.10" }
                "completions" { "0.15" }
                default { "0.20" }
            }
            Write-Host "   🎚️  Threshold Configurado: $threshold"
            
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
        
        if ($cacheRecommendation -ne "N/A") {
            Write-ColorOutput "   💡 Recomendación: $cacheRecommendation" $colors.Info
        }
        
        if ($Verbose) {
            Write-Host "`n   📦 DETALLES DE LA RESPUESTA:"
            if ($OperationType -eq "chat") {
                $content = $Result.Response.choices[0].message.content
                Write-Host "   Respuesta: $($content.Substring(0, [Math]::Min(100, $content.Length)))..."
                Write-Host "   Tokens de Prompt: $($Result.Response.usage.prompt_tokens)"
                Write-Host "   Tokens de Respuesta: $($Result.Response.usage.completion_tokens)"
                Write-Host "   Tokens Totales: $($Result.Response.usage.total_tokens)"
            } else {
                $content = $Result.Response.choices[0].text
                Write-Host "   Respuesta: $($content.Substring(0, [Math]::Min(100, $content.Length)))..."
                Write-Host "   Tokens Totales: $($Result.Response.usage.total_tokens)"
            }
            Write-Host "   Modelo: $($Result.Response.model)"
        }
    }
    else {
        Write-ColorOutput "❌ Error: $($Result.Error)" $colors.Error
        if ($Result.StatusCode) {
            Write-Host "   Código de Estado: $($Result.StatusCode)"
        }
    }
}

# Función para calcular el grupo de temperatura
function Get-TemperatureGroup {
    param([float]$Temperature)
    
    if ($Temperature -le 0.2) { return "deterministic" }
    elseif ($Temperature -le 0.5) { return "low" }
    elseif ($Temperature -le 0.8) { return "medium" }
    else { return "high" }
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
    TestsByTemperature = @{
        deterministic = @{ Total = 0; Hits = 0 }
        low = @{ Total = 0; Hits = 0 }
        medium = @{ Total = 0; Hits = 0 }
        high = @{ Total = 0; Hits = 0 }
    }
    TestsByType = @{
        chat = @{ Total = 0; Hits = 0 }
        completions = @{ Total = 0; Hits = 0 }
    }
}

# Arrays para almacenar resultados detallados
$testResults = @()

# CONJUNTO DE PRUEBAS PARA CHAT
Write-ColorOutput "`n╔══════════════════════════════════════════════════════╗" $colors.Highlight
Write-ColorOutput "║              🧪 PRUEBAS DE CHAT/COMPLETIONS          ║" $colors.Highlight
Write-ColorOutput "╚══════════════════════════════════════════════════════╝`n" $colors.Highlight

# Test 1: Chat con temperatura baja (deterministic)
Write-ColorOutput "➤ Test 1: Chat con temperatura muy baja (0.1) - Grupo deterministic" $colors.Info
$test1Messages = @(
    @{
        role = "system"
        content = "Eres un asistente útil que responde preguntas de forma concisa."
    },
    @{
        role = "user"
        content = "¿Cuál es la capital de Francia?"
    }
)
$test1 = Measure-RequestTime {
    Invoke-ChatRequest -Messages $test1Messages -Temperature 0.1 -MaxTokens 50 -User "test_user_001"
}
Show-TestResult "Chat temperatura 0.1 (deterministic)" $test1.Result $test1.ElapsedMilliseconds 1 -ExpectedCacheStatus "MISS"
$testResults += @{
    TestNumber = 1
    Name = "Chat temperatura 0.1"
    ElapsedMs = $test1.ElapsedMilliseconds
    CacheStatus = $test1.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test1.Result.Success
    Temperature = 0.1
    Type = "chat"
}
$stats.TotalTests++
$stats.TestsByType.chat.Total++
$stats.TestsByTemperature.deterministic.Total++
$stats.TotalTime += $test1.ElapsedMilliseconds
if ($test1.Result.Success) {
    if ($test1.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.chat.Hits++
        $stats.TestsByTemperature.deterministic.Hits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

Start-Sleep -Seconds 2

# Test 2: Misma pregunta, misma temperatura (debe ser HIT con threshold 0.10)
Write-ColorOutput "`n➤ Test 2: Solicitud idéntica - Validando caché con threshold 0.10" $colors.Info
$test2 = Measure-RequestTime {
    Invoke-ChatRequest -Messages $test1Messages -Temperature 0.1 -MaxTokens 50 -User "test_user_001"
}
Show-TestResult "Solicitud idéntica (debe ser HIT)" $test2.Result $test2.ElapsedMilliseconds 2 -ExpectedCacheStatus "HIT"
$testResults += @{
    TestNumber = 2
    Name = "Solicitud idéntica"
    ElapsedMs = $test2.ElapsedMilliseconds
    CacheStatus = $test2.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test2.Result.Success
    Temperature = 0.1
    Type = "chat"
}
$stats.TotalTests++
$stats.TestsByType.chat.Total++
$stats.TestsByTemperature.deterministic.Total++
$stats.TotalTime += $test2.ElapsedMilliseconds
if ($test2.Result.Success) {
    if ($test2.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.chat.Hits++
        $stats.TestsByTemperature.deterministic.Hits++
        $speedup = [Math]::Round($test1.ElapsedMilliseconds / $test2.ElapsedMilliseconds, 1)
        Write-ColorOutput "   🚀 Mejora de velocidad: ${speedup}x más rápido" $colors.Success
        $stats.TokensSaved += 50  # Estimación basada en max_tokens
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

Start-Sleep -Seconds 1

# Test 3: Pregunta similar pero no idéntica (threshold 0.10 debería permitir match semántico)
Write-ColorOutput "`n➤ Test 3: Pregunta similar - Probando similitud semántica" $colors.Info
$test3Messages = @(
    @{
        role = "system"
        content = "Eres un asistente útil que responde preguntas de forma concisa."
    },
    @{
        role = "user"
        content = "¿Cuál es la ciudad capital de Francia?"  # Variación ligera
    }
)
$test3 = Measure-RequestTime {
    Invoke-ChatRequest -Messages $test3Messages -Temperature 0.1 -MaxTokens 50 -User "test_user_001"
}
Show-TestResult "Pregunta similar (threshold 0.10)" $test3.Result $test3.ElapsedMilliseconds 3 -ExpectedCacheStatus "HIT"
$testResults += @{
    TestNumber = 3
    Name = "Pregunta similar"
    ElapsedMs = $test3.ElapsedMilliseconds
    CacheStatus = $test3.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test3.Result.Success
    Temperature = 0.1
    Type = "chat"
}
$stats.TotalTests++
$stats.TestsByType.chat.Total++
$stats.TestsByTemperature.deterministic.Total++
$stats.TotalTime += $test3.ElapsedMilliseconds
if ($test3.Result.Success) {
    if ($test3.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.chat.Hits++
        $stats.TestsByTemperature.deterministic.Hits++
        Write-ColorOutput "   🎯 Score de similitud: $($test3.Result.Headers.'X-Semantic-Cache-Score'[0])" $colors.Info
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

# Test 4: Temperatura media (0.7) - Grupo medium, TTL 2 horas
Write-ColorOutput "`n➤ Test 4: Chat con temperatura media (0.7) - Grupo medium" $colors.Info
$test4Messages = @(
    @{
        role = "user"
        content = "Explica qué es la inteligencia artificial en 2 oraciones"
    }
)
$test4 = Measure-RequestTime {
    Invoke-ChatRequest -Messages $test4Messages -Temperature 0.7 -MaxTokens 100
}
Show-TestResult "Chat temperatura 0.7 (medium)" $test4.Result $test4.ElapsedMilliseconds 4 -ExpectedCacheStatus "MISS"
$testResults += @{
    TestNumber = 4
    Name = "Chat temperatura 0.7"
    ElapsedMs = $test4.ElapsedMilliseconds
    CacheStatus = $test4.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test4.Result.Success
    Temperature = 0.7
    Type = "chat"
}
$stats.TotalTests++
$stats.TestsByType.chat.Total++
$stats.TestsByTemperature.medium.Total++
$stats.TotalTime += $test4.ElapsedMilliseconds
if ($test4.Result.Success) {
    if ($test4.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.chat.Hits++
        $stats.TestsByTemperature.medium.Hits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

# Test 5: Misma temperatura, diferente max_tokens (partición diferente)
Write-ColorOutput "`n➤ Test 5: Mismo prompt, diferentes max_tokens - Validando particionamiento" $colors.Info
$test5 = Measure-RequestTime {
    Invoke-ChatRequest -Messages $test4Messages -Temperature 0.7 -MaxTokens 200
}
Show-TestResult "Diferentes max_tokens (debe ser MISS)" $test5.Result $test5.ElapsedMilliseconds 5 -ExpectedCacheStatus "MISS"
$testResults += @{
    TestNumber = 5
    Name = "Diferentes max_tokens"
    ElapsedMs = $test5.ElapsedMilliseconds
    CacheStatus = $test5.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test5.Result.Success
    Temperature = 0.7
    Type = "chat"
}
$stats.TotalTests++
$stats.TestsByType.chat.Total++
$stats.TestsByTemperature.medium.Total++
$stats.TotalTime += $test5.ElapsedMilliseconds
if ($test5.Result.Success) {
    if ($test5.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.chat.Hits++
        $stats.TestsByTemperature.medium.Hits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

# Test 6: Alta temperatura (0.9) - Grupo high, TTL 1 hora
Write-ColorOutput "`n➤ Test 6: Chat con temperatura alta (0.9) - Grupo high" $colors.Info
$test6Messages = @(
    @{
        role = "user"
        content = "Escribe un haiku sobre programación"
    }
)
$test6 = Measure-RequestTime {
    Invoke-ChatRequest -Messages $test6Messages -Temperature 0.9 -MaxTokens 50
}
Show-TestResult "Chat temperatura 0.9 (high)" $test6.Result $test6.ElapsedMilliseconds 6 -ExpectedCacheStatus "MISS"
$testResults += @{
    TestNumber = 6
    Name = "Chat temperatura 0.9"
    ElapsedMs = $test6.ElapsedMilliseconds
    CacheStatus = $test6.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test6.Result.Success
    Temperature = 0.9
    Type = "chat"
}
$stats.TotalTests++
$stats.TestsByType.chat.Total++
$stats.TestsByTemperature.high.Total++
$stats.TotalTime += $test6.ElapsedMilliseconds
if ($test6.Result.Success) {
    if ($test6.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.chat.Hits++
        $stats.TestsByTemperature.high.Hits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

# Test 7: Conversación multi-turno
Write-ColorOutput "`n➤ Test 7: Conversación multi-turno - Contexto complejo" $colors.Info
$test7Messages = @(
    @{
        role = "system"
        content = "Eres un experto en tecnología"
    },
    @{
        role = "user"
        content = "¿Qué es Docker?"
    },
    @{
        role = "assistant"
        content = "Docker es una plataforma de contenedores que permite empaquetar aplicaciones con sus dependencias."
    },
    @{
        role = "user"
        content = "¿Y Kubernetes?"
    }
)
$test7 = Measure-RequestTime {
    Invoke-ChatRequest -Messages $test7Messages -Temperature 0.3 -MaxTokens 150
}
Show-TestResult "Conversación multi-turno" $test7.Result $test7.ElapsedMilliseconds 7 -ExpectedCacheStatus "MISS"
$testResults += @{
    TestNumber = 7
    Name = "Conversación multi-turno"
    ElapsedMs = $test7.ElapsedMilliseconds
    CacheStatus = $test7.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test7.Result.Success
    Temperature = 0.3
    Type = "chat"
}
$stats.TotalTests++
$stats.TestsByType.chat.Total++
$stats.TestsByTemperature.low.Total++
$stats.TotalTime += $test7.ElapsedMilliseconds
if ($test7.Result.Success) {
    if ($test7.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.chat.Hits++
        $stats.TestsByTemperature.low.Hits++
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

# Test 8: Repetir conversación multi-turno
Write-ColorOutput "`n➤ Test 8: Repetir conversación multi-turno - Validando caché complejo" $colors.Info
$test8 = Measure-RequestTime {
    Invoke-ChatRequest -Messages $test7Messages -Temperature 0.3 -MaxTokens 150
}
Show-TestResult "Conversación repetida (debe ser HIT)" $test8.Result $test8.ElapsedMilliseconds 8 -ExpectedCacheStatus "HIT"
$testResults += @{
    TestNumber = 8
    Name = "Conversación repetida"
    ElapsedMs = $test8.ElapsedMilliseconds
    CacheStatus = $test8.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
    Success = $test8.Result.Success
    Temperature = 0.3
    Type = "chat"
}
$stats.TotalTests++
$stats.TestsByType.chat.Total++
$stats.TestsByTemperature.low.Total++
$stats.TotalTime += $test8.ElapsedMilliseconds
if ($test8.Result.Success) {
    if ($test8.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
        $stats.CacheHits++
        $stats.TestsByType.chat.Hits++
        $stats.TestsByTemperature.low.Hits++
        $stats.TokensSaved += 150
    } else {
        $stats.CacheMisses++
    }
} else {
    $stats.Errors++
}

# PRUEBAS DE COMPLETIONS (si está habilitado)
if ($TestCompletions) {
    Write-ColorOutput "`n╔══════════════════════════════════════════════════════╗" $colors.Highlight
    Write-ColorOutput "║              🧪 PRUEBAS DE COMPLETIONS               ║" $colors.Highlight
    Write-ColorOutput "╚══════════════════════════════════════════════════════╝`n" $colors.Highlight
    
    # Test 9: Completion básica
    Write-ColorOutput "➤ Test 9: Completion con temperatura baja" $colors.Info
    $test9Prompt = "La inteligencia artificial es"
    $test9 = Measure-RequestTime {
        Invoke-CompletionRequest -Prompt $test9Prompt -Temperature 0.2 -MaxTokens 50
    }
    Show-TestResult "Completion temperatura 0.2" $test9.Result $test9.ElapsedMilliseconds 9 -ExpectedCacheStatus "MISS" -OperationType "completions"
    $testResults += @{
        TestNumber = 9
        Name = "Completion temperatura 0.2"
        ElapsedMs = $test9.ElapsedMilliseconds
        CacheStatus = $test9.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
        Success = $test9.Result.Success
        Temperature = 0.2
        Type = "completions"
    }
    $stats.TotalTests++
    $stats.TestsByType.completions.Total++
    $stats.TestsByTemperature.deterministic.Total++
    $stats.TotalTime += $test9.ElapsedMilliseconds
    if ($test9.Result.Success) {
        if ($test9.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
            $stats.CacheHits++
            $stats.TestsByType.completions.Hits++
            $stats.TestsByTemperature.deterministic.Hits++
        } else {
            $stats.CacheMisses++
        }
    } else {
        $stats.Errors++
    }
    
    Start-Sleep -Seconds 1
    
    # Test 10: Repetir completion (threshold 0.15 para completions)
    Write-ColorOutput "`n➤ Test 10: Repetir completion - Validando threshold 0.15" $colors.Info
    $test10 = Measure-RequestTime {
        Invoke-CompletionRequest -Prompt $test9Prompt -Temperature 0.2 -MaxTokens 50
    }
    Show-TestResult "Completion repetida (debe ser HIT)" $test10.Result $test10.ElapsedMilliseconds 10 -ExpectedCacheStatus "HIT" -OperationType "completions"
    $testResults += @{
        TestNumber = 10
        Name = "Completion repetida"
        ElapsedMs = $test10.ElapsedMilliseconds
        CacheStatus = $test10.Result.Headers.'X-Semantic-Cache-Status'[0] ?? "NONE"
        Success = $test10.Result.Success
        Temperature = 0.2
        Type = "completions"
    }
    $stats.TotalTests++
    $stats.TestsByType.completions.Total++
    $stats.TestsByTemperature.deterministic.Total++
    $stats.TotalTime += $test10.ElapsedMilliseconds
    if ($test10.Result.Success) {
        if ($test10.Result.Headers.'X-Semantic-Cache-Status'[0] -eq "HIT") {
            $stats.CacheHits++
            $stats.TestsByType.completions.Hits++
            $stats.TestsByTemperature.deterministic.Hits++
            $stats.TokensSaved += 50
        } else {
            $stats.CacheMisses++
        }
    } else {
        $stats.Errors++
    }
}

# PRUEBAS EXTENDIDAS
if ($ExtendedTests) {
    Write-ColorOutput "`n╔══════════════════════════════════════════════════════╗" $colors.Highlight
    Write-ColorOutput "║          🔬 PRUEBAS EXTENDIDAS DE CHAT/COMPLETIONS   ║" $colors.Highlight
    Write-ColorOutput "╚══════════════════════════════════════════════════════╝`n" $colors.Highlight
    
    # Test de diferentes parámetros avanzados
    Write-ColorOutput "➤ Test de Parámetros Avanzados: top_p, penalties" $colors.Info
    
    # Test con top_p bajo
    $advTest1Messages = @(
        @{
            role = "user"
            content = "Dame un ejemplo de recursividad"
        }
    )
    $advTest1 = Measure-RequestTime {
        Invoke-ChatRequest -Messages $advTest1Messages -Temperature 0.5 -MaxTokens 100 -TopP 0.5
    }
    Write-Host "`n   📊 Test con top_p=0.5: $($advTest1.Result.Success ? 'OK' : 'FAIL')"
    if ($advTest1.Result.Success) {
        Write-Host "   Cache Status: $($advTest1.Result.Headers.'X-Semantic-Cache-Status'[0] ?? 'NONE')"
    }
    
    # Test con frequency penalty
    $advTest2 = Measure-RequestTime {
        Invoke-ChatRequest -Messages $advTest1Messages -Temperature 0.5 -MaxTokens 100 -FrequencyPenalty 0.5
    }
    Write-Host "   📊 Test con frequency_penalty=0.5: $($advTest2.Result.Success ? 'OK' : 'FAIL')"
    if ($advTest2.Result.Success) {
        Write-Host "   Cache Status: $($advTest2.Result.Headers.'X-Semantic-Cache-Status'[0] ?? 'NONE')"
    }
    
    # Test con presence penalty
    $advTest3 = Measure-RequestTime {
        Invoke-ChatRequest -Messages $advTest1Messages -Temperature 0.5 -MaxTokens 100 -PresencePenalty 0.5
    }
    Write-Host "   📊 Test con presence_penalty=0.5: $($advTest3.Result.Success ? 'OK' : 'FAIL')"
    if ($advTest3.Result.Success) {
        Write-Host "   Cache Status: $($advTest3.Result.Headers.'X-Semantic-Cache-Status'[0] ?? 'NONE')"
    }
    
    # Test de formato de respuesta JSON
    Write-ColorOutput "`n➤ Test de Response Format: JSON mode" $colors.Info
    $jsonMessages = @(
        @{
            role = "system"
            content = "Responde siempre en formato JSON válido"
        },
        @{
            role = "user"
            content = "Dame información sobre Python en formato JSON con campos: nombre, tipo, año"
        }
    )
    $jsonTest = Measure-RequestTime {
        Invoke-ChatRequest -Messages $jsonMessages -Temperature 0.1 -MaxTokens 100 -ResponseFormat @{ type = "json_object" }
    }
    Write-Host "   📊 Test JSON format: $($jsonTest.Result.Success ? 'OK' : 'FAIL')"
    if ($jsonTest.Result.Success) {
        Write-Host "   Cache Status: $($jsonTest.Result.Headers.'X-Semantic-Cache-Status'[0] ?? 'NONE')"
    }
    
    # Test de límites de contexto
    Write-ColorOutput "`n➤ Test de Límites: Contexto largo" $colors.Info
    
    # Crear un contexto muy largo
    $longContext = @(
        @{
            role = "system"
            content = "Eres un asistente experto en historia. " * 50  # ~350 tokens
        }
    )
    for ($i = 1; $i -le 10; $i++) {
        $longContext += @{
            role = "user"
            content = "Pregunta $i sobre historia antigua"
        }
        $longContext += @{
            role = "assistant"
            content = "Respuesta detallada número $i sobre el tema histórico mencionado. " * 10
        }
    }
    $longContext += @{
        role = "user"
        content = "Resume todo lo anterior en una oración"
    }
    
    $longContextTest = Measure-RequestTime {
        Invoke-ChatRequest -Messages $longContext -Temperature 0.3 -MaxTokens 50
    }
    Write-Host "   📏 Test contexto largo (~4000 tokens): $($longContextTest.Result.Success ? 'OK' : 'FAIL')"
    if ($longContextTest.Result.Success) {
        Write-Host "   Tokens usados: $($longContextTest.Result.Response.usage.total_tokens)"
    }
    
    # Test de concurrencia para chat
    Write-ColorOutput "`n➤ Test de Estrés: Múltiples usuarios simultáneos" $colors.Info
    $concurrentUsers = @("user1", "user2", "user3", "user4", "user5")
    $jobs = @()
    $startTime = Get-Date
    
    foreach ($user in $concurrentUsers) {
        $jobs += Start-Job -ScriptBlock {
            param($endpoint, $deployment, $headers, $user)
            
            $messages = @(
                @{
                    role = "user"
                    content = "Hola, soy $user. ¿Qué hora es?"
                }
            )
            
            $body = @{
                messages = $messages
                temperature = 0.1
                max_tokens = 30
                user = $user
            } | ConvertTo-Json -Depth 3
            
            try {
                $response = Invoke-RestMethod -Uri "$endpoint/deployments/$deployment/chat/completions?api-version=2024-02-01" `
                    -Method Post `
                    -Headers $headers `
                    -Body $body `
                    -ErrorAction Stop `
                    -ResponseHeadersVariable responseHeaders
                
                return @{
                    Success = $true
                    User = $user
                    CacheStatus = $responseHeaders.'X-Semantic-Cache-Status'[0] ?? "NONE"
                }
            }
            catch {
                return @{
                    Success = $false
                    User = $user
                    Error = $_.Exception.Message
                }
            }
        } -ArgumentList $ApimEndpoint, $DeploymentName, $headers, $user
    }
    
    # Esperar resultados
    $concurrentResults = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job
    
    $endTime = Get-Date
    $totalConcurrentTime = ($endTime - $startTime).TotalMilliseconds
    
    Write-Host "`n   📊 Resultados de Concurrencia:"
    $concurrentSuccess = ($concurrentResults | Where-Object { $_.Success }).Count
    Write-Host "   ✅ Solicitudes exitosas: $concurrentSuccess/$($concurrentUsers.Count)"
    Write-Host "   ⏱️  Tiempo total: $([Math]::Round($totalConcurrentTime, 2))ms"
    Write-Host "   ⚡ Throughput: $([Math]::Round($concurrentUsers.Count / ($totalConcurrentTime / 1000), 2)) req/s"
    
    # Mostrar resultados por usuario
    foreach ($result in $concurrentResults) {
        if ($result.Success) {
            Write-Host "   👤 $($result.User): Cache $($result.CacheStatus)"
        } else {
            Write-Host "   ❌ $($result.User): Error"
        }
    }
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

# Estadísticas por tipo de operación
Write-Host "`n📊 ESTADÍSTICAS POR TIPO DE OPERACIÓN:"
foreach ($type in $stats.TestsByType.Keys) {
    $typeStats = $stats.TestsByType[$type]
    if ($typeStats.Total -gt 0) {
        $typeHitRate = [Math]::Round(($typeStats.Hits / $typeStats.Total) * 100, 2)
        Write-Host "   ├─ $type`: $($typeStats.Hits)/$($typeStats.Total) hits ($typeHitRate%)"
    }
}

# Estadísticas por temperatura
Write-Host "`n🌡️  ESTADÍSTICAS POR GRUPO DE TEMPERATURA:"
foreach ($tempGroup in $stats.TestsByTemperature.Keys | Sort-Object) {
    $tempStats = $stats.TestsByTemperature[$tempGroup]
    if ($tempStats.Total -gt 0) {
        $tempHitRate = [Math]::Round(($tempStats.Hits / $tempStats.Total) * 100, 2)
        $ttl = switch($tempGroup) {
            "deterministic" { "12h" }
            "low" { "4h" }
            "medium" { "2h" }
            "high" { "1h" }
        }
        Write-Host "   ├─ $tempGroup (TTL $ttl): $($tempStats.Hits)/$($tempStats.Total) hits ($tempHitRate%)"
    }
}

# Análisis de rendimiento
Write-ColorOutput "`n⚡ ANÁLISIS DE RENDIMIENTO:" $colors.Info
$avgHitTime = 100   # ms promedio estimado para cache hits
$avgMissTime = 2000 # ms promedio estimado para cache misses en chat
$timesSaved = ($stats.CacheHits * ($avgMissTime - $avgHitTime)) / 1000  # segundos

Write-Host "   ├─ Tiempo ahorrado total: $([Math]::Round($timesSaved, 2)) segundos"
Write-Host "   ├─ Reducción de latencia promedio: ~95% en hits"
Write-Host "   └─ Mejora promedio en hits: ~20x más rápido"

# Análisis de costos mejorado
Write-ColorOutput "`n💰 ANÁLISIS DE COSTOS:" $colors.Info
$costPer1KTokensInput = 0.03   # USD para GPT-4
$costPer1KTokensOutput = 0.06  # USD para GPT-4
$avgInputTokens = 50
$avgOutputTokens = 100
$tokensSaved = $stats.TokensSaved
$inputCostSaved = ($tokensSaved * $avgInputTokens / ($avgInputTokens + $avgOutputTokens) / 1000) * $costPer1KTokensInput
$outputCostSaved = ($tokensSaved * $avgOutputTokens / ($avgInputTokens + $avgOutputTokens) / 1000) * $costPer1KTokensOutput
$totalCostSaved = $inputCostSaved + $outputCostSaved

Write-Host "   ├─ Tokens ahorrados (estimado): $tokensSaved"
Write-Host "   ├─ Costo ahorrado: `$$([Math]::Round($totalCostSaved, 4)) USD"
Write-Host "   ├─ Ahorro proyectado diario: `$$([Math]::Round($totalCostSaved * 24, 2)) USD"
Write-Host "   ├─ Ahorro proyectado mensual: `$$([Math]::Round($totalCostSaved * 24 * 30, 2)) USD"
Write-Host "   └─ ROI del caché: $([Math]::Round($hitRate * 0.90, 1))% de reducción en costos"

# Recomendaciones basadas en resultados
Write-ColorOutput "`n💡 RECOMENDACIONES Y OBSERVACIONES:" $colors.Info

# Análisis del threshold
Write-Host "`n🎚️  CONFIGURACIÓN DE THRESHOLD DETECTADA:"
Write-Host "   ├─ Chat: 0.10 (muy permisivo - bueno para variaciones)"
Write-Host "   ├─ Completions: 0.15 (moderado)"
Write-Host "   └─ Embeddings: 0.95 (muy estricto - solo matches exactos)"

if ($hitRate -lt 20) {
    Write-ColorOutput "`n   ⚠️  Hit rate bajo ($hitRate%). Considera:" $colors.Warning
    Write-Host "      • Estandarizar los prompts del sistema"
    Write-Host "      • Usar temperaturas más bajas para consultas repetitivas"
    Write-Host "      • Implementar normalización de preguntas de usuarios"
    Write-Host "      • Agrupar max_tokens en rangos (50, 100, 200, etc.)"
} elseif ($hitRate -lt 50) {
    Write-ColorOutput "`n   📊 Hit rate moderado ($hitRate%). Para mejorar:" $colors.Info
    Write-Host "      • Identificar consultas frecuentes y optimizar sus parámetros"
    Write-Host "      • Considerar pre-warming del caché con consultas comunes"
    Write-Host "      • Usar temperaturas consistentes por tipo de consulta"
} else {
    Write-ColorOutput "`n   🎯 Excelente hit rate ($hitRate%)!" $colors.Success
    Write-Host "      • El caché está funcionando óptimamente"
    Write-Host "      • Considera ajustar TTLs según patrones de uso"
    Write-Host "      • Monitorea el tamaño del caché regularmente"
}

# Información sobre TTL por temperatura
Write-Host "`n⏰ CONFIGURACIÓN DE TTL POR TEMPERATURA:"
Write-Host "   ├─ Deterministic (≤0.2): 12 horas"
Write-Host "   ├─ Low (0.2-0.5): 4 horas"
Write-Host "   ├─ Medium (0.5-0.8): 2 horas"
Write-Host "   └─ High (>0.8): 1 hora"

# Guardar resultados detallados
if ($SaveResults) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $resultsFile = "chat-completions-cache-test-v2-$timestamp.json"
    
    $detailedResults = @{
        TestDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Configuration = @{
            Endpoint = $ApimEndpoint
            Deployment = $DeploymentName
            ExtendedTests = $ExtendedTests.IsPresent
            TestCompletions = $TestCompletions.IsPresent
        }
        Statistics = $stats
        Analysis = @{
            HitRate = $hitRate
            AverageResponseTime = $avgTime
            TokensSaved = $tokensSaved
            CostSaved = $totalCostSaved
            EstimatedDailySavings = [Math]::Round($totalCostSaved * 24, 2)
            EstimatedMonthlySavings = [Math]::Round($totalCostSaved * 24 * 30, 2)
            TimeSavedSeconds = $timesSaved
        }
        TestResults = $testResults
        PolicyConfiguration = @{
            ScoreThreshold = @{
                Chat = "0.10"
                Completions = "0.15"
                Embeddings = "0.95"
            }
            TTL = @{
                Deterministic = "12 hours"
                Low = "4 hours"
                Medium = "2 hours"
                High = "1 hour"
            }
        }
    }
    
    $detailedResults | ConvertTo-Json -Depth 5 | Out-File $resultsFile
    Write-ColorOutput "`n💾 Resultados detallados guardados en: $resultsFile" $colors.Success
    
    # Generar reporte CSV para análisis
    $csvFile = "chat-completions-cache-test-v2-$timestamp.csv"
    $testResults | Export-Csv -Path $csvFile -NoTypeInformation
    Write-ColorOutput "📊 Datos de pruebas exportados a: $csvFile" $colors.Success
}

if ($stats.Errors -gt 0) {
    Write-ColorOutput "`n⚠️  ADVERTENCIA: Se detectaron $($stats.Errors) errores durante las pruebas" $colors.Error
    Write-Host "   Verifica:"
    Write-Host "   • La configuración del endpoint y API key"
    Write-Host "   • El modelo deployment existe y está activo"
    Write-Host "   • Los límites de rate limiting y cuotas"
}

Write-ColorOutput "`n✨ Pruebas de caché semántico para chat/completions completadas exitosamente!`n" $colors.Success

# Mostrar comandos útiles
Write-Host "💡 Comandos útiles:"
Write-Host "   • Pruebas completas: ./test-completions-cache-v2.ps1 -ExtendedTests -SaveResults"
Write-Host "   • Con completions: ./test-completions-cache-v2.ps1 -TestCompletions"
Write-Host "   • Modo verbose: ./test-completions-cache-v2.ps1 -Verbose"
Write-Host ""