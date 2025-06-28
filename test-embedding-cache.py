import os
import time
import json
import asyncio
from datetime import datetime
from typing import List, Dict, Optional, Tuple
import numpy as np
from openai import AzureOpenAI
import requests
from colorama import init, Fore, Back, Style
import statistics

# Inicializar colorama para Windows
init(autoreset=True)

# Configuración predeterminada
DEFAULT_APIM_ENDPOINT = "https://apim0-m5gd7y67cu5b6.azure-api.net/openai"
DEFAULT_DEPLOYMENT = "text-embedding-3-large"
DEFAULT_API_VERSION = "2024-02-01"

class EmbeddingCacheTest:
    def __init__(self, endpoint: str, api_key: str, deployment: str = DEFAULT_DEPLOYMENT):
        """Inicializa el cliente de pruebas para embedding cache."""
        self.endpoint = endpoint
        self.api_key = api_key
        self.deployment = deployment
        self.results = []
        self.cache_hits = 0
        self.cache_misses = 0
        
    def print_header(self, text: str):
        """Imprime un header formateado."""
        print(f"\n{Fore.CYAN}{'='*80}")
        print(f"{Fore.CYAN}{text.center(80)}")
        print(f"{Fore.CYAN}{'='*80}\n")
        
    def print_test(self, test_name: str, test_num: int, total: int):
        """Imprime información del test actual."""
        print(f"{Fore.YELLOW}▶ Test {test_num}/{total}: {test_name}")
        print(f"{Fore.YELLOW}{'─'*60}")
        
    def create_embedding_request(self, input_text: str, 
                               input_type: str = "query",
                               dimensions: int = 3072,
                               user: str = "test-user") -> Dict:
        """Crea un request de embedding con parámetros personalizados."""
        return {
            "input": input_text,
            "model": self.deployment,
            "input_type": input_type,
            "dimensions": dimensions,
            "user": user
        }
        
    def make_request(self, data: Dict) -> Tuple[Dict, Dict, float]:
        """Realiza una solicitud a la API y retorna respuesta, headers y tiempo."""
        url = f"{self.endpoint}/deployments/{self.deployment}/embeddings?api-version={DEFAULT_API_VERSION}"
        
        headers = {
            "api-key": self.api_key,
            "Content-Type": "application/json"
        }
        
        start_time = time.time()
        response = requests.post(url, json=data, headers=headers)
        elapsed_time = time.time() - start_time
        
        return response.json(), dict(response.headers), elapsed_time
        
    def analyze_cache_response(self, headers: Dict, elapsed_time: float, expected_hit: bool) -> Dict:
        """Analiza los headers de respuesta para determinar el estado del cache."""
        cache_status = headers.get('X-Semantic-Cache-Status', 'UNKNOWN')
        cache_score = headers.get('X-Semantic-Cache-Score', 'N/A')
        cache_ttl = headers.get('X-Cache-TTL-Days', 'N/A')
        response_time_header = headers.get('X-Response-Time-Ms', 'N/A')
        
        is_hit = cache_status == 'HIT'
        
        # Actualizar contadores
        if is_hit:
            self.cache_hits += 1
        else:
            self.cache_misses += 1
            
        # Determinar si el resultado es el esperado
        result_correct = is_hit == expected_hit
        
        return {
            'cache_status': cache_status,
            'cache_score': cache_score,
            'cache_ttl': cache_ttl,
            'response_time': elapsed_time,
            'response_time_header': response_time_header,
            'is_hit': is_hit,
            'expected_hit': expected_hit,
            'result_correct': result_correct
        }
        
    def print_result(self, test_name: str, result: Dict):
        """Imprime el resultado de un test de forma visual."""
        status_color = Fore.GREEN if result['is_hit'] else Fore.RED
        result_icon = "✓" if result['result_correct'] else "✗"
        result_color = Fore.GREEN if result['result_correct'] else Fore.RED
        
        print(f"\n{Fore.WHITE}Resultado:")
        print(f"  └─ Cache Status: {status_color}{result['cache_status']}")
        print(f"  └─ Cache Score: {result['cache_score']}")
        print(f"  └─ TTL (días): {result['cache_ttl']}")
        print(f"  └─ Tiempo de respuesta: {result['response_time']:.3f}s")
        print(f"  └─ Validación: {result_color}{result_icon} (Esperado: {'HIT' if result['expected_hit'] else 'MISS'})")
        
    def run_embedding_tests(self):
        """Ejecuta la suite completa de pruebas de embedding cache."""
        self.print_header("PRUEBAS DE CACHÉ SEMÁNTICO - EMBEDDINGS")
        
        print(f"{Fore.WHITE}📋 Configuración:")
        print(f"  └─ Endpoint: {self.endpoint}")
        print(f"  └─ Deployment: {self.deployment}")
        print(f"  └─ Score Threshold: 0.95 (configurado en APIM)")
        print(f"  └─ TTL: 30 días para documentos, 14 días para queries")
        
        tests = [
            # Test 1: Primera consulta (MISS esperado)
            {
                "name": "Primera consulta - Query simple",
                "data": self.create_embedding_request("What are the best practices for Python?"),
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 2: Misma consulta exacta (HIT esperado con threshold 0.95)
            {
                "name": "Consulta idéntica - Debe ser HIT",
                "data": self.create_embedding_request("What are the best practices for Python?"),
                "expected_hit": True,
                "wait": 1
            },
            
            # Test 3: Consulta similar pero no idéntica (MISS esperado con threshold 0.95)
            {
                "name": "Consulta similar - Debe ser MISS (threshold alto)",
                "data": self.create_embedding_request("What are the best practices for Python programming?"),
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 4: Document embedding con input_type diferente
            {
                "name": "Document embedding - Tipo diferente",
                "data": self.create_embedding_request(
                    "Python is a high-level programming language...",
                    input_type="document"
                ),
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 5: Mismo documento (HIT esperado)
            {
                "name": "Mismo documento - Debe ser HIT",
                "data": self.create_embedding_request(
                    "Python is a high-level programming language...",
                    input_type="document"
                ),
                "expected_hit": True,
                "wait": 1
            },
            
            # Test 6: Diferentes dimensiones (MISS por particionamiento)
            {
                "name": "Query con dimensiones diferentes",
                "data": self.create_embedding_request(
                    "What are the best practices for Python?",
                    dimensions=1536
                ),
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 7: Diferente usuario (MISS por particionamiento)
            {
                "name": "Query con usuario diferente",
                "data": self.create_embedding_request(
                    "What are the best practices for Python?",
                    user="different-user"
                ),
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 8: Batch embedding
            {
                "name": "Batch embedding - Array de inputs",
                "data": {
                    "input": ["Query 1", "Query 2", "Query 3"],
                    "model": self.deployment
                },
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 9: Mismo batch (HIT esperado)
            {
                "name": "Mismo batch - Debe ser HIT",
                "data": {
                    "input": ["Query 1", "Query 2", "Query 3"],
                    "model": self.deployment
                },
                "expected_hit": True,
                "wait": 1
            },
            
            # Test 10: Passage type
            {
                "name": "Passage embedding - Texto largo",
                "data": self.create_embedding_request(
                    "This is a longer passage that contains multiple sentences. " * 10,
                    input_type="passage"
                ),
                "expected_hit": False,
                "wait": 0
            }
        ]
        
        # Ejecutar tests
        test_results = []
        for i, test in enumerate(tests, 1):
            self.print_test(test["name"], i, len(tests))
            
            if test["wait"] > 0:
                print(f"{Fore.BLUE}⏳ Esperando {test['wait']}s para asegurar propagación del cache...")
                time.sleep(test["wait"])
                
            # Hacer request
            response, headers, elapsed_time = self.make_request(test["data"])
            
            # Analizar resultado
            result = self.analyze_cache_response(headers, elapsed_time, test["expected_hit"])
            
            # Guardar resultado
            test_result = {
                "test_name": test["name"],
                "timestamp": datetime.now().isoformat(),
                "request_data": test["data"],
                "response_time": elapsed_time,
                **result
            }
            test_results.append(test_result)
            
            # Mostrar resultado
            self.print_result(test["name"], result)
            
        # Resumen final
        self.print_summary(test_results)
        
        # Guardar resultados
        self.save_results(test_results)
        
    def print_summary(self, results: List[Dict]):
        """Imprime un resumen de todas las pruebas."""
        self.print_header("RESUMEN DE PRUEBAS")
        
        total_tests = len(results)
        passed_tests = sum(1 for r in results if r['result_correct'])
        hit_rate = (self.cache_hits / total_tests) * 100 if total_tests > 0 else 0
        
        # Tiempos de respuesta
        hit_times = [r['response_time'] for r in results if r['is_hit']]
        miss_times = [r['response_time'] for r in results if not r['is_hit']]
        
        avg_hit_time = statistics.mean(hit_times) if hit_times else 0
        avg_miss_time = statistics.mean(miss_times) if miss_times else 0
        
        print(f"{Fore.WHITE}📊 Estadísticas Generales:")
        print(f"  └─ Total de pruebas: {total_tests}")
        print(f"  └─ Pruebas exitosas: {Fore.GREEN}{passed_tests}/{total_tests}")
        print(f"  └─ Cache Hits: {Fore.GREEN}{self.cache_hits}")
        print(f"  └─ Cache Misses: {Fore.RED}{self.cache_misses}")
        print(f"  └─ Hit Rate: {Fore.CYAN}{hit_rate:.1f}%")
        
        print(f"\n{Fore.WHITE}⏱️  Tiempos de Respuesta:")
        print(f"  └─ Promedio Cache Hit: {Fore.GREEN}{avg_hit_time:.3f}s")
        print(f"  └─ Promedio Cache Miss: {Fore.YELLOW}{avg_miss_time:.3f}s")
        if avg_miss_time > 0:
            speedup = avg_miss_time / avg_hit_time if avg_hit_time > 0 else 0
            print(f"  └─ Mejora de velocidad: {Fore.CYAN}{speedup:.1f}x")
            
        print(f"\n{Fore.WHITE}💰 Estimación de Ahorros:")
        # Asumiendo $0.0004 por 1K tokens para embeddings
        cost_per_miss = 0.0004  # Por embedding
        cost_per_hit = 0.00001  # Costo mínimo de cache
        
        total_cost_without_cache = total_tests * cost_per_miss
        actual_cost = (self.cache_misses * cost_per_miss) + (self.cache_hits * cost_per_hit)
        savings = total_cost_without_cache - actual_cost
        
        print(f"  └─ Costo sin cache: ${total_cost_without_cache:.4f}")
        print(f"  └─ Costo con cache: ${actual_cost:.4f}")
        print(f"  └─ Ahorro: {Fore.GREEN}${savings:.4f} ({(savings/total_cost_without_cache*100):.1f}%)")
        
    def save_results(self, results: List[Dict]):
        """Guarda los resultados en un archivo JSON."""
        filename = f"embedding_cache_test_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        
        summary = {
            "test_date": datetime.now().isoformat(),
            "endpoint": self.endpoint,
            "deployment": self.deployment,
            "total_tests": len(results),
            "cache_hits": self.cache_hits,
            "cache_misses": self.cache_misses,
            "hit_rate": (self.cache_hits / len(results)) * 100 if results else 0,
            "results": results
        }
        
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(summary, f, indent=2, ensure_ascii=False)
            
        print(f"\n{Fore.GREEN}✅ Resultados guardados en: {filename}")

def get_parameters():
    """Solicita los parámetros de configuración."""
    print(f"{Fore.CYAN}🔧 CONFIGURACIÓN DE PRUEBAS DE EMBEDDING CACHE")
    print(f"{Fore.CYAN}{'='*60}")
    print(f"{Fore.WHITE}Presiona Enter para usar los valores predeterminados\n")
    
    endpoint = input(f"APIM Endpoint [{DEFAULT_APIM_ENDPOINT}]: ").strip() or DEFAULT_APIM_ENDPOINT
    api_key = input(f"Subscription Key: ").strip()
    
    if not api_key:
        print(f"{Fore.RED}❌ Error: La Subscription Key es requerida")
        exit(1)
        
    deployment = input(f"Embedding Deployment [{DEFAULT_DEPLOYMENT}]: ").strip() or DEFAULT_DEPLOYMENT
    
    return {
        'endpoint': endpoint,
        'api_key': api_key,
        'deployment': deployment
    }

def main():
    """Función principal."""
    try:
        # Obtener configuración
        config = get_parameters()
        
        # Crear instancia de pruebas
        tester = EmbeddingCacheTest(
            endpoint=config['endpoint'],
            api_key=config['api_key'],
            deployment=config['deployment']
        )
        
        # Ejecutar pruebas
        tester.run_embedding_tests()
        
        # Preguntar si ejecutar pruebas adicionales
        print(f"\n{Fore.YELLOW}¿Deseas ejecutar pruebas adicionales? (concurrencia, límites)")
        additional = input("(s/N): ").strip().lower()
        
        if additional == 's':
            # Aquí se pueden agregar pruebas adicionales
            print(f"{Fore.CYAN}Pruebas adicionales no implementadas en esta versión")
            
    except KeyboardInterrupt:
        print(f"\n\n{Fore.YELLOW}⚠️  Prueba interrumpida por el usuario")
    except Exception as e:
        print(f"\n{Fore.RED}❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()