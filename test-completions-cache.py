import os
import time
import json
import asyncio
from datetime import datetime
from typing import List, Dict, Optional, Tuple
import requests
from colorama import init, Fore, Back, Style
import statistics

# Inicializar colorama para Windows
init(autoreset=True)

# Configuración predeterminada
DEFAULT_APIM_ENDPOINT = "https://apim0-m5gd7y67cu5b6.azure-api.net/openai"
DEFAULT_GPT_DEPLOYMENT = "gpt-4"
DEFAULT_API_VERSION = "2024-02-01"

class CompletionsCacheTest:
    def __init__(self, endpoint: str, api_key: str, deployment: str = DEFAULT_GPT_DEPLOYMENT):
        """Inicializa el cliente de pruebas para completions cache."""
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
        
    def create_chat_request(self, 
                          messages: List[Dict],
                          temperature: float = 0.7,
                          max_tokens: int = 800,
                          user: str = "test-user",
                          **kwargs) -> Dict:
        """Crea un request de chat completion con parámetros personalizados."""
        request = {
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "user": user,
            "model": self.deployment
        }
        
        # Agregar parámetros adicionales si se proporcionan
        for key, value in kwargs.items():
            request[key] = value
            
        return request
        
    def make_request(self, data: Dict, operation: str = "chat/completions") -> Tuple[Dict, Dict, float]:
        """Realiza una solicitud a la API y retorna respuesta, headers y tiempo."""
        url = f"{self.endpoint}/deployments/{self.deployment}/{operation}?api-version={DEFAULT_API_VERSION}"
        
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
        cache_ttl_hours = headers.get('X-Cache-TTL-Hours', 'N/A')
        recommended_ttl = headers.get('X-Recommended-TTL-Hours', 'N/A')
        response_time_header = headers.get('X-Response-Time-Ms', 'N/A')
        optimization_tip = headers.get('X-Cache-Optimization-Tip', 'N/A')
        
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
            'cache_ttl_hours': cache_ttl_hours,
            'recommended_ttl': recommended_ttl,
            'response_time': elapsed_time,
            'response_time_header': response_time_header,
            'optimization_tip': optimization_tip,
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
        print(f"  └─ TTL actual: {result['cache_ttl_hours']} horas")
        print(f"  └─ TTL recomendado: {result['recommended_ttl']} horas")
        print(f"  └─ Tiempo de respuesta: {result['response_time']:.3f}s")
        print(f"  └─ Tip: {Fore.BLUE}{result['optimization_tip']}")
        print(f"  └─ Validación: {result_color}{result_icon} (Esperado: {'HIT' if result['expected_hit'] else 'MISS'})")
        
    def run_completion_tests(self):
        """Ejecuta la suite completa de pruebas de completion cache."""
        self.print_header("PRUEBAS DE CACHÉ SEMÁNTICO - CHAT COMPLETIONS")
        
        print(f"{Fore.WHITE}📋 Configuración:")
        print(f"  └─ Endpoint: {self.endpoint}")
        print(f"  └─ Deployment: {self.deployment}")
        print(f"  └─ Score Threshold: 0.10 (configurado en APIM)")
        print(f"  └─ TTL Base: 2 horas (fijo en política)")
        
        tests = [
            # Test 1: Primera consulta con temperatura media (MISS esperado)
            {
                "name": "Primera consulta - Temperatura media (0.7)",
                "data": self.create_chat_request(
                    messages=[
                        {"role": "system", "content": "You are a helpful assistant."},
                        {"role": "user", "content": "What are Python best practices?"}
                    ],
                    temperature=0.7
                ),
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 2: Misma consulta exacta (HIT esperado)
            {
                "name": "Consulta idéntica - Debe ser HIT",
                "data": self.create_chat_request(
                    messages=[
                        {"role": "system", "content": "You are a helpful assistant."},
                        {"role": "user", "content": "What are Python best practices?"}
                    ],
                    temperature=0.7
                ),
                "expected_hit": True,
                "wait": 2
            },
            
            # Test 3: Consulta similar (HIT posible con threshold 0.10)
            {
                "name": "Consulta similar - Posible HIT (threshold bajo)",
                "data": self.create_chat_request(
                    messages=[
                        {"role": "system", "content": "You are a helpful assistant."},
                        {"role": "user", "content": "What are the Python best practices?"}
                    ],
                    temperature=0.7
                ),
                "expected_hit": True,  # Podría ser HIT con threshold 0.10
                "wait": 0
            },
            
            # Test 4: Temperatura determinística (0.0)
            {
                "name": "Consulta con temperatura 0.0 (determinística)",
                "data": self.create_chat_request(
                    messages=[
                        {"role": "system", "content": "You are a helpful assistant."},
                        {"role": "user", "content": "List exactly 3 Python best practices"}
                    ],
                    temperature=0.0,
                    max_tokens=100
                ),
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 5: Misma consulta determinística (HIT esperado)
            {
                "name": "Repetir consulta determinística - Debe ser HIT",
                "data": self.create_chat_request(
                    messages=[
                        {"role": "system", "content": "You are a helpful assistant."},
                        {"role": "user", "content": "List exactly 3 Python best practices"}
                    ],
                    temperature=0.0,
                    max_tokens=100
                ),
                "expected_hit": True,
                "wait": 1
            },
            
            # Test 6: Alta temperatura (creativa)
            {
                "name": "Consulta con temperatura alta (0.9)",
                "data": self.create_chat_request(
                    messages=[
                        {"role": "system", "content": "You are a creative writer."},
                        {"role": "user", "content": "Write a haiku about Python"}
                    ],
                    temperature=0.9,
                    max_tokens=50
                ),
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 7: Diferente usuario (MISS por particionamiento)
            {
                "name": "Misma consulta, diferente usuario",
                "data": self.create_chat_request(
                    messages=[
                        {"role": "system", "content": "You are a helpful assistant."},
                        {"role": "user", "content": "What are Python best practices?"}
                    ],
                    temperature=0.7,
                    user="different-user"
                ),
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 8: Diferentes max_tokens (podría afectar particionamiento)
            {
                "name": "Misma consulta, diferentes max_tokens",
                "data": self.create_chat_request(
                    messages=[
                        {"role": "system", "content": "You are a helpful assistant."},
                        {"role": "user", "content": "What are Python best practices?"}
                    ],
                    temperature=0.7,
                    max_tokens=2000  # Cambia el grupo de tokens
                ),
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 9: Con frequency_penalty
            {
                "name": "Consulta con frequency_penalty",
                "data": self.create_chat_request(
                    messages=[
                        {"role": "system", "content": "You are a helpful assistant."},
                        {"role": "user", "content": "Explain recursion in programming"}
                    ],
                    temperature=0.5,
                    frequency_penalty=0.5,
                    presence_penalty=0.0
                ),
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 10: Conversación multi-turno
            {
                "name": "Conversación multi-turno",
                "data": self.create_chat_request(
                    messages=[
                        {"role": "system", "content": "You are a helpful assistant."},
                        {"role": "user", "content": "What is Python?"},
                        {"role": "assistant", "content": "Python is a high-level programming language..."},
                        {"role": "user", "content": "What are its main uses?"}
                    ],
                    temperature=0.7
                ),
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 11: Con funciones/herramientas
            {
                "name": "Consulta con funciones definidas",
                "data": self.create_chat_request(
                    messages=[
                        {"role": "system", "content": "You are a helpful assistant."},
                        {"role": "user", "content": "What's the weather like?"}
                    ],
                    temperature=0.7,
                    functions=[{
                        "name": "get_weather",
                        "description": "Get the current weather",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "location": {"type": "string"}
                            }
                        }
                    }]
                ),
                "expected_hit": False,
                "wait": 0
            },
            
            # Test 12: Repetir primera consulta después de tiempo
            {
                "name": "Repetir primera consulta (verificar persistencia)",
                "data": self.create_chat_request(
                    messages=[
                        {"role": "system", "content": "You are a helpful assistant."},
                        {"role": "user", "content": "What are Python best practices?"}
                    ],
                    temperature=0.7
                ),
                "expected_hit": True,
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
            
            # Mostrar preview de la respuesta si es exitosa
            if response.get('choices'):
                content = response['choices'][0]['message']['content']
                preview = content[:100] + "..." if len(content) > 100 else content
                print(f"\n{Fore.GRAY}📝 Preview respuesta: {preview}")
            
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
        if avg_miss_time > 0 and avg_hit_time > 0:
            speedup = avg_miss_time / avg_hit_time
            print(f"  └─ Mejora de velocidad: {Fore.CYAN}{speedup:.1f}x")
            
        # Análisis por grupo de temperatura
        print(f"\n{Fore.WHITE}🌡️  Análisis por Temperatura:")
        temp_groups = {}
        for r in results:
            temp = r['request_data'].get('temperature', 0.7)
            if temp <= 0.2:
                group = "deterministic"
            elif temp <= 0.5:
                group = "low"
            elif temp <= 0.8:
                group = "medium"
            else:
                group = "high"
            
            if group not in temp_groups:
                temp_groups[group] = {'hits': 0, 'total': 0}
            
            temp_groups[group]['total'] += 1
            if r['is_hit']:
                temp_groups[group]['hits'] += 1
                
        for group, stats in temp_groups.items():
            group_hit_rate = (stats['hits'] / stats['total'] * 100) if stats['total'] > 0 else 0
            print(f"  └─ {group}: {stats['hits']}/{stats['total']} hits ({group_hit_rate:.1f}%)")
            
        print(f"\n{Fore.WHITE}💰 Estimación de Ahorros:")
        # Asumiendo costos de GPT-4
        # Input: $0.03 per 1K tokens, Output: $0.06 per 1K tokens
        # Promedio: ~500 tokens por request
        avg_tokens = 500
        cost_per_miss = (avg_tokens / 1000) * 0.045  # Promedio input/output
        cost_per_hit = cost_per_miss * 0.05  # 5% del costo por overhead de cache
        
        total_cost_without_cache = total_tests * cost_per_miss
        actual_cost = (self.cache_misses * cost_per_miss) + (self.cache_hits * cost_per_hit)
        savings = total_cost_without_cache - actual_cost
        
        print(f"  └─ Costo sin cache: ${total_cost_without_cache:.4f}")
        print(f"  └─ Costo con cache: ${actual_cost:.4f}")
        print(f"  └─ Ahorro: {Fore.GREEN}${savings:.4f} ({(savings/total_cost_without_cache*100):.1f}%)")
        
        # Proyección mensual
        requests_per_day = 1000  # Estimación
        monthly_savings = savings * (requests_per_day / total_tests) * 30
        print(f"  └─ Ahorro mensual proyectado: {Fore.GREEN}${monthly_savings:.2f}")
        
    def save_results(self, results: List[Dict]):
        """Guarda los resultados en un archivo JSON."""
        filename = f"completions_cache_test_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        
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
    print(f"{Fore.CYAN}🔧 CONFIGURACIÓN DE PRUEBAS DE COMPLETIONS CACHE")
    print(f"{Fore.CYAN}{'='*60}")
    print(f"{Fore.WHITE}Presiona Enter para usar los valores predeterminados\n")
    
    endpoint = input(f"APIM Endpoint [{DEFAULT_APIM_ENDPOINT}]: ").strip() or DEFAULT_APIM_ENDPOINT
    api_key = input(f"Subscription Key: ").strip()
    
    if not api_key:
        print(f"{Fore.RED}❌ Error: La Subscription Key es requerida")
        exit(1)
        
    deployment = input(f"GPT Deployment [{DEFAULT_GPT_DEPLOYMENT}]: ").strip() or DEFAULT_GPT_DEPLOYMENT
    
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
        tester = CompletionsCacheTest(
            endpoint=config['endpoint'],
            api_key=config['api_key'],
            deployment=config['deployment']
        )
        
        # Ejecutar pruebas
        tester.run_completion_tests()
        
        # Preguntar si ejecutar pruebas adicionales
        print(f"\n{Fore.YELLOW}¿Deseas ejecutar pruebas de estrés? (100 requests concurrentes)")
        additional = input("(s/N): ").strip().lower()
        
        if additional == 's':
            print(f"{Fore.CYAN}Ejecutando pruebas de concurrencia...")
            # Aquí se pueden implementar pruebas de concurrencia con asyncio
            print(f"{Fore.YELLOW}Pruebas de concurrencia no implementadas en esta versión")
            
    except KeyboardInterrupt:
        print(f"\n\n{Fore.YELLOW}⚠️  Prueba interrumpida por el usuario")
    except Exception as e:
        print(f"\n{Fore.RED}❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()