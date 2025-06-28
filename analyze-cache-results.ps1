# analyze-cache-results.ps1
# Script para analizar y visualizar resultados de pruebas de caché semántico
# Compatible con resultados de test-embedding-cache-v2.ps1 y test-completions-cache-v2.ps1
# Versión: 1.0

param(
    [Parameter(Mandatory=$false)]
    [string]$ResultsPath = ".",
    
    [Parameter(Mandatory=$false)]
    [string]$Pattern = "*cache-test-v2*.json",
    
    [Parameter(Mandatory=$false)]
    [switch]$GenerateReport,
    
    [Parameter(Mandatory=$false)]
    [switch]$CompareResults
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

# Función para cargar y analizar archivos de resultados
function Get-CacheTestResults {
    param(
        [string]$Path,
        [string]$FilePattern
    )
    
    $results = @()
    $files = Get-ChildItem -Path $Path -Filter $FilePattern -File
    
    foreach ($file in $files) {
        try {
            $content = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $results += [PSCustomObject]@{
                FileName = $file.Name
                FilePath = $file.FullName
                TestDate = $content.TestDate
                TestType = if ($file.Name -match "embedding") { "Embeddings" } else { "Chat/Completions" }
                Configuration = $content.Configuration
                Statistics = $content.Statistics
                Analysis = $content.Analysis
                PolicyConfiguration = $content.PolicyConfiguration
            }
        }
        catch {
            Write-ColorOutput "Error al leer $($file.Name): $_" $colors.Error
        }
    }
    
    return $results
}

# Función para mostrar resumen de un resultado
function Show-ResultSummary {
    param(
        [PSCustomObject]$Result
    )
    
    Write-ColorOutput "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" $colors.Info
    Write-ColorOutput "📊 $($Result.TestType) - $($Result.TestDate)" $colors.Highlight
    Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" $colors.Info
    
    Write-Host "`n📋 Configuración:"
    Write-Host "   Endpoint: $($Result.Configuration.Endpoint)"
    Write-Host "   Deployment: $($Result.Configuration.Deployment)"
    
    Write-Host "`n📈 Métricas Principales:"
    Write-Host "   Total de pruebas: $($Result.Statistics.TotalTests)"
    Write-Host "   Cache Hits: $($Result.Statistics.CacheHits)"
    Write-Host "   Cache Misses: $($Result.Statistics.CacheMisses)"
    Write-Host "   Hit Rate: $($Result.Analysis.HitRate)%"
    Write-Host "   Tiempo promedio: $($Result.Analysis.AverageResponseTime)ms"
    
    Write-Host "`n💰 Análisis de Costos:"
    Write-Host "   Tokens ahorrados: $($Result.Analysis.TokensSaved)"
    Write-Host "   Costo ahorrado: `$$($Result.Analysis.CostSaved)"
    Write-Host "   Ahorro mensual estimado: `$$($Result.Analysis.EstimatedMonthlySavings)"
    
    if ($Result.TestType -eq "Embeddings") {
        Write-Host "`n📊 Estadísticas por Tipo:"
        foreach ($type in @("Query", "Document", "Passage")) {
            if ($Result.Statistics.TestsByType.$type) {
                $typeStats = $Result.Statistics.TestsByType.$type
                if ($typeStats.Total -gt 0) {
                    $hitRate = [Math]::Round(($typeStats.Hits / $typeStats.Total) * 100, 2)
                    Write-Host "   $type`: $($typeStats.Hits)/$($typeStats.Total) ($hitRate%)"
                }
            }
        }
    }
    else {
        Write-Host "`n🌡️  Estadísticas por Temperatura:"
        foreach ($temp in @("deterministic", "low", "medium", "high")) {
            if ($Result.Statistics.TestsByTemperature.$temp) {
                $tempStats = $Result.Statistics.TestsByTemperature.$temp
                if ($tempStats.Total -gt 0) {
                    $hitRate = [Math]::Round(($tempStats.Hits / $tempStats.Total) * 100, 2)
                    Write-Host "   $temp`: $($tempStats.Hits)/$($tempStats.Total) ($hitRate%)"
                }
            }
        }
    }
}

# Función para comparar múltiples resultados
function Compare-Results {
    param(
        [array]$Results
    )
    
    if ($Results.Count -lt 2) {
        Write-ColorOutput "Se necesitan al menos 2 resultados para comparar" $colors.Warning
        return
    }
    
    Write-ColorOutput "`n╔══════════════════════════════════════════════════════╗" $colors.Highlight
    Write-ColorOutput "║            📊 COMPARACIÓN DE RESULTADOS              ║" $colors.Highlight
    Write-ColorOutput "╚══════════════════════════════════════════════════════╝`n" $colors.Highlight
    
    # Agrupar por tipo
    $embeddingResults = $Results | Where-Object { $_.TestType -eq "Embeddings" }
    $chatResults = $Results | Where-Object { $_.TestType -eq "Chat/Completions" }
    
    # Comparar resultados de embeddings
    if ($embeddingResults.Count -gt 1) {
        Write-ColorOutput "`n🔤 EMBEDDINGS - Evolución del Hit Rate:" $colors.Info
        $embeddingResults | Sort-Object TestDate | ForEach-Object {
            $trend = ""
            if ($script:lastEmbeddingHitRate) {
                $diff = $_.Analysis.HitRate - $script:lastEmbeddingHitRate
                $trend = if ($diff -gt 0) { "↑ +$([Math]::Round($diff, 2))%" } 
                        elseif ($diff -lt 0) { "↓ $([Math]::Round($diff, 2))%" }
                        else { "→ 0%" }
            }
            $script:lastEmbeddingHitRate = $_.Analysis.HitRate
            
            Write-Host "   $($_.TestDate): $($_.Analysis.HitRate)% $trend"
        }
    }
    
    # Comparar resultados de chat
    if ($chatResults.Count -gt 1) {
        Write-ColorOutput "`n💬 CHAT/COMPLETIONS - Evolución del Hit Rate:" $colors.Info
        $chatResults | Sort-Object TestDate | ForEach-Object {
            $trend = ""
            if ($script:lastChatHitRate) {
                $diff = $_.Analysis.HitRate - $script:lastChatHitRate
                $trend = if ($diff -gt 0) { "↑ +$([Math]::Round($diff, 2))%" } 
                        elseif ($diff -lt 0) { "↓ $([Math]::Round($diff, 2))%" }
                        else { "→ 0%" }
            }
            $script:lastChatHitRate = $_.Analysis.HitRate
            
            Write-Host "   $($_.TestDate): $($_.Analysis.HitRate)% $trend"
        }
    }
    
    # Estadísticas agregadas
    Write-ColorOutput "`n📊 ESTADÍSTICAS AGREGADAS:" $colors.Info
    
    $totalTests = ($Results | Measure-Object -Property { $_.Statistics.TotalTests } -Sum).Sum
    $totalHits = ($Results | Measure-Object -Property { $_.Statistics.CacheHits } -Sum).Sum
    $totalMisses = ($Results | Measure-Object -Property { $_.Statistics.CacheMisses } -Sum).Sum
    $avgHitRate = [Math]::Round(($totalHits / $totalTests) * 100, 2)
    $totalTokensSaved = ($Results | Measure-Object -Property { $_.Analysis.TokensSaved } -Sum).Sum
    $totalCostSaved = ($Results | Measure-Object -Property { $_.Analysis.CostSaved } -Sum).Sum
    
    Write-Host "   Total de pruebas ejecutadas: $totalTests"
    Write-Host "   Total de cache hits: $totalHits"
    Write-Host "   Hit rate promedio global: $avgHitRate%"
    Write-Host "   Tokens totales ahorrados: $totalTokensSaved"
    Write-Host "   Costo total ahorrado: `$$([Math]::Round($totalCostSaved, 2))"
    
    # Mejor y peor rendimiento
    $bestResult = $Results | Sort-Object { $_.Analysis.HitRate } -Descending | Select-Object -First 1
    $worstResult = $Results | Sort-Object { $_.Analysis.HitRate } | Select-Object -First 1
    
    Write-Host "`n🏆 Mejor rendimiento:"
    Write-Host "   $($bestResult.TestType) - $($bestResult.TestDate): $($bestResult.Analysis.HitRate)%"
    
    Write-Host "`n⚠️  Menor rendimiento:"
    Write-Host "   $($worstResult.TestType) - $($worstResult.TestDate): $($worstResult.Analysis.HitRate)%"
}

# Función para generar reporte detallado
function Generate-DetailedReport {
    param(
        [array]$Results,
        [string]$OutputPath
    )
    
    $reportContent = @"
# Reporte de Análisis de Caché Semántico
Generado: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Resumen Ejecutivo

Total de archivos analizados: $($Results.Count)
Período analizado: $($Results | Sort-Object TestDate | Select-Object -First 1 -ExpandProperty TestDate) - $($Results | Sort-Object TestDate -Descending | Select-Object -First 1 -ExpandProperty TestDate)

### Métricas Globales

"@

    $totalTests = ($Results | Measure-Object -Property { $_.Statistics.TotalTests } -Sum).Sum
    $totalHits = ($Results | Measure-Object -Property { $_.Statistics.CacheHits } -Sum).Sum
    $avgHitRate = [Math]::Round(($totalHits / $totalTests) * 100, 2)
    $totalCostSaved = ($Results | Measure-Object -Property { $_.Analysis.CostSaved } -Sum).Sum
    $projectedMonthlySavings = $totalCostSaved * 30 * 24 / $Results.Count

    $reportContent += @"
- **Total de pruebas ejecutadas**: $totalTests
- **Total de cache hits**: $totalHits
- **Hit rate promedio**: $avgHitRate%
- **Costo total ahorrado en pruebas**: `$$([Math]::Round($totalCostSaved, 2))
- **Ahorro mensual proyectado**: `$$([Math]::Round($projectedMonthlySavings, 2))

## Análisis por Tipo de Operación

### Embeddings

"@

    $embeddingResults = $Results | Where-Object { $_.TestType -eq "Embeddings" }
    if ($embeddingResults) {
        $avgEmbeddingHitRate = ($embeddingResults | Measure-Object -Property { $_.Analysis.HitRate } -Average).Average
        $reportContent += @"
- **Pruebas de embeddings**: $($embeddingResults.Count)
- **Hit rate promedio**: $([Math]::Round($avgEmbeddingHitRate, 2))%
- **Threshold configurado**: 0.95 (muy estricto)
- **TTL**: 7-14 días según tipo

"@
    }

    $reportContent += @"
### Chat/Completions

"@

    $chatResults = $Results | Where-Object { $_.TestType -eq "Chat/Completions" }
    if ($chatResults) {
        $avgChatHitRate = ($chatResults | Measure-Object -Property { $_.Analysis.HitRate } -Average).Average
        $reportContent += @"
- **Pruebas de chat/completions**: $($chatResults.Count)
- **Hit rate promedio**: $([Math]::Round($avgChatHitRate, 2))%
- **Threshold configurado**: 0.10-0.15 (permisivo)
- **TTL**: 1-12 horas según temperatura

"@
    }

    $reportContent += @"

## Recomendaciones

### Para Mejorar el Hit Rate

1. **Embeddings** (Hit rate actual: $([Math]::Round($avgEmbeddingHitRate, 2))%):
   - Implementar normalización de texto antes de generar embeddings
   - Usar dimensiones consistentes para el mismo tipo de contenido
   - Pre-computar embeddings para documentos estáticos

2. **Chat/Completions** (Hit rate actual: $([Math]::Round($avgChatHitRate, 2))%):
   - Estandarizar prompts del sistema
   - Usar temperaturas más bajas para consultas repetitivas
   - Agrupar max_tokens en rangos predefinidos

### Optimización de Costos

- **Ahorro actual**: `$$([Math]::Round($totalCostSaved, 2)) en pruebas
- **Potencial mensual**: `$$([Math]::Round($projectedMonthlySavings, 2))
- **ROI estimado**: $([Math]::Round($avgHitRate * 0.9, 1))% de reducción en costos de API

### Próximos Pasos

1. Monitorear métricas de caché en producción
2. Ajustar thresholds según patrones de uso reales
3. Implementar alertas para degradación del hit rate
4. Considerar pre-warming del caché para consultas frecuentes

## Datos Detallados por Prueba

"@

    foreach ($result in $Results | Sort-Object TestDate -Descending) {
        $reportContent += @"

### $($result.TestType) - $($result.TestDate)

- **Archivo**: $($result.FileName)
- **Hit Rate**: $($result.Analysis.HitRate)%
- **Pruebas**: $($result.Statistics.TotalTests) (Hits: $($result.Statistics.CacheHits), Misses: $($result.Statistics.CacheMisses))
- **Tiempo promedio**: $($result.Analysis.AverageResponseTime)ms
- **Tokens ahorrados**: $($result.Analysis.TokensSaved)
- **Costo ahorrado**: `$$($result.Analysis.CostSaved)

"@
    }

    # Guardar reporte
    $reportPath = Join-Path $OutputPath "cache-analysis-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
    $reportContent | Out-File $reportPath -Encoding UTF8
    
    Write-ColorOutput "`n📄 Reporte detallado guardado en: $reportPath" $colors.Success
    
    # También generar versión HTML si es posible
    try {
        # Intentar convertir Markdown a HTML (requiere un módulo adicional)
        $htmlPath = $reportPath -replace '\.md$', '.html'
        $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Reporte de Caché Semántico</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        h1, h2, h3 { color: #333; }
        h1 { border-bottom: 2px solid #0066cc; padding-bottom: 10px; }
        h2 { border-bottom: 1px solid #ccc; padding-bottom: 5px; margin-top: 30px; }
        ul { margin: 10px 0; }
        li { margin: 5px 0; }
        strong { color: #0066cc; }
        code { background: #f4f4f4; padding: 2px 4px; border-radius: 3px; }
    </style>
</head>
<body>
$($reportContent -replace '\n', '<br/>' -replace '#{3}\s*(.+)', '<h3>$1</h3>' -replace '#{2}\s*(.+)', '<h2>$1</h2>' -replace '#{1}\s*(.+)', '<h1>$1</h1>' -replace '\*\*(.+?)\*\*', '<strong>$1</strong>' -replace '`(.+?)`', '<code>$1</code>' -replace '^-\s*', '<li>' -replace '<li>(.+?)(<br/>|$)', '<li>$1</li>')
</body>
</html>
"@
        $htmlContent | Out-File $htmlPath -Encoding UTF8
        Write-ColorOutput "📄 Reporte HTML guardado en: $htmlPath" $colors.Success
    }
    catch {
        # Si falla la conversión a HTML, no es crítico
    }
}

# MAIN
Clear-Host
Write-ColorOutput "`n╔══════════════════════════════════════════════════════╗" $colors.Info
Write-ColorOutput "║       📊 ANÁLISIS DE RESULTADOS DE CACHÉ SEMÁNTICO   ║" $colors.Highlight
Write-ColorOutput "╚══════════════════════════════════════════════════════╝`n" $colors.Info

# Cargar resultados
Write-ColorOutput "🔍 Buscando archivos de resultados..." $colors.Info
$results = Get-CacheTestResults -Path $ResultsPath -FilePattern $Pattern

if ($results.Count -eq 0) {
    Write-ColorOutput "`n❌ No se encontraron archivos de resultados con el patrón '$Pattern' en '$ResultsPath'" $colors.Error
    Write-Host "`nAsegúrate de ejecutar primero los scripts de prueba con -SaveResults"
    return
}

Write-ColorOutput "✅ Se encontraron $($results.Count) archivo(s) de resultados`n" $colors.Success

# Mostrar resumen de cada resultado
foreach ($result in $results | Sort-Object TestDate -Descending) {
    Show-ResultSummary -Result $result
}

# Comparar resultados si hay múltiples
if ($CompareResults -and $results.Count -gt 1) {
    Compare-Results -Results $results
}

# Generar reporte detallado si se solicita
if ($GenerateReport) {
    Write-ColorOutput "`n📝 Generando reporte detallado..." $colors.Info
    Generate-DetailedReport -Results $results -OutputPath $ResultsPath
}

# Resumen final y recomendaciones
Write-ColorOutput "`n╔══════════════════════════════════════════════════════╗" $colors.Highlight
Write-ColorOutput "║                 💡 CONCLUSIONES                      ║" $colors.Highlight
Write-ColorOutput "╚══════════════════════════════════════════════════════╝" $colors.Highlight

$avgHitRate = ($results | Measure-Object -Property { $_.Analysis.HitRate } -Average).Average

if ($avgHitRate -gt 60) {
    Write-ColorOutput "`n🎯 Excelente rendimiento del caché (Hit rate promedio: $([Math]::Round($avgHitRate, 2))%)" $colors.Success
    Write-Host "   El sistema está optimizado y generando ahorros significativos."
} elseif ($avgHitRate -gt 30) {
    Write-ColorOutput "`n📊 Rendimiento moderado del caché (Hit rate promedio: $([Math]::Round($avgHitRate, 2))%)" $colors.Info
    Write-Host "   Hay oportunidades de mejora para aumentar la eficiencia."
} else {
    Write-ColorOutput "`n⚠️  Rendimiento bajo del caché (Hit rate promedio: $([Math]::Round($avgHitRate, 2))%)" $colors.Warning
    Write-Host "   Se requiere optimización urgente para mejorar el ROI."
}

Write-Host "`n📌 Acciones recomendadas:"
Write-Host "   1. Ejecutar pruebas regularmente para monitorear tendencias"
Write-Host "   2. Ajustar configuración según los patrones observados"
Write-Host "   3. Implementar métricas de producción para validar resultados"

Write-ColorOutput "`n✨ Análisis completado exitosamente!`n" $colors.Success