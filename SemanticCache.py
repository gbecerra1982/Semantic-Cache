import os
import time
import json
from datetime import datetime
from typing import List, Dict, Optional, Tuple
import numpy as np
from openai import AzureOpenAI
from azure.ai.inference import ChatCompletionsClient
from azure.ai.inference.models import SystemMessage, UserMessage
from azure.core.credentials import AzureKeyCredential
import faiss
import pickle

# Función para solicitar parámetros
def get_parameters():
    """Solicita los parámetros de configuración con valores predeterminados."""
    print("🔧 CONFIGURACIÓN DE AZURE AI FOUNDRY")
    print("=" * 60)
    print("Presiona Enter para usar los valores predeterminados\n")
    
    # SDK a usar
    print("Selecciona el SDK a usar:")
    print("1. Azure OpenAI SDK con endpoint de OpenAI (predeterminado)")
    print("2. Azure OpenAI SDK con endpoint de Foundry")
    print("3. Azure AI Foundry SDK (experimental)")
    sdk_choice = input("Opción [1]: ").strip() or "1"
    
    if sdk_choice == "3":
        # Configuración para Azure AI Foundry SDK
        endpoint = input(f"Azure AI Foundry endpoint [{DEFAULT_FOUNDRY_ENDPOINT}]: ").strip() or DEFAULT_FOUNDRY_ENDPOINT
        api_key = input(f"API Key [{DEFAULT_API_KEY[:20]}...]: ").strip() or DEFAULT_API_KEY
        
        # Deployment names para Foundry
        gpt_deployment = input(f"GPT Deployment name [{DEFAULT_GPT_DEPLOYMENT}]: ").strip() or DEFAULT_GPT_DEPLOYMENT
        embedding_deployment = input(f"Embedding Deployment name [{DEFAULT_EMBEDDING_DEPLOYMENT}]: ").strip() or DEFAULT_EMBEDDING_DEPLOYMENT
        
        return {
            'use_foundry': True,
            'endpoint': endpoint,
            'api_key': api_key,
            'gpt_deployment': gpt_deployment,
            'embedding_deployment': embedding_deployment,
            'api_version': None
        }
    elif sdk_choice == "2":
        # Configuración para Azure OpenAI SDK con endpoint de Foundry
        endpoint = input(f"Azure OpenAI endpoint [{DEFAULT_OPENAI_ENDPOINT}]: ").strip() or DEFAULT_OPENAI_ENDPOINT
        api_key = input(f"API Key [{DEFAULT_API_KEY[:20]}...]: ").strip() or DEFAULT_API_KEY
        api_version = input(f"API Version [{DEFAULT_API_VERSION}]: ").strip() or DEFAULT_API_VERSION
        
        # Deployment names
        gpt_deployment = input(f"GPT Deployment name [{DEFAULT_GPT_DEPLOYMENT}]: ").strip() or DEFAULT_GPT_DEPLOYMENT
        embedding_deployment = input(f"Embedding Deployment name [{DEFAULT_EMBEDDING_DEPLOYMENT}]: ").strip() or DEFAULT_EMBEDDING_DEPLOYMENT
        
        return {
            'use_foundry': False,
            'endpoint': endpoint,
            'api_key': api_key,
            'gpt_deployment': gpt_deployment,
            'embedding_deployment': embedding_deployment,
            'api_version': api_version
        }
    else:
        # Configuración estándar para Azure OpenAI
        endpoint = input(f"Azure OpenAI endpoint [Tu endpoint]: ").strip()
        api_key = input(f"API Key: ").strip()
        api_version = input(f"API Version [{DEFAULT_API_VERSION}]: ").strip() or DEFAULT_API_VERSION
        
        # Deployment names
        gpt_deployment = input(f"GPT Deployment name [{DEFAULT_GPT_DEPLOYMENT}]: ").strip() or DEFAULT_GPT_DEPLOYMENT
        embedding_deployment = input(f"Embedding Deployment name [{DEFAULT_EMBEDDING_DEPLOYMENT}]: ").strip() or DEFAULT_EMBEDDING_DEPLOYMENT
        
        return {
            'use_foundry': False,
            'endpoint': endpoint,
            'api_key': api_key,
            'gpt_deployment': gpt_deployment,
            'embedding_deployment': embedding_deployment,
            'api_version': api_version
        }

# Valores predeterminados
DEFAULT_FOUNDRY_ENDPOINT = "https://foundry-proyecto1.services.ai.azure.com/api/projects/myFirstProject"
DEFAULT_OPENAI_ENDPOINT = "https://foundry-proyecto1.openai.azure.com/"
DEFAULT_API_KEY = "44E5Jtv6MfBOtx7565zFDoGXV8hTHeUrokBk7DdArzC69NAFC7ZxJQQJ99BFAC4f1cMXJ3w3AAAAACOGVYsT"
DEFAULT_API_VERSION = "2024-02-01"
DEFAULT_GPT_DEPLOYMENT = "gpt-4.1"
DEFAULT_EMBEDDING_DEPLOYMENT = "text-embedding"

# Configuración de caché
CACHE_FILE = "semantic_cache.pkl"
INDEX_FILE = "semantic_index.faiss"
SIMILARITY_THRESHOLD = 0.85  # Umbral de similitud para considerar un hit de caché

class SemanticCache:
    def __init__(self, embedding_dimension: int = None, config: Dict = None):
        """Inicializa la caché semántica con FAISS."""
        self.embedding_dimension = embedding_dimension
        self.index = None  # Se inicializará después de conocer la dimensión
        self.cache: Dict[int, Dict] = {}
        self.cache_hits = 0
        self.cache_misses = 0
        self.config = config or {}
        self._initialized = False
        
    def _initialize_index(self, dimension: int):
        """Inicializa el índice FAISS con la dimensión correcta."""
        if not self._initialized:
            self.embedding_dimension = dimension
            self.index = faiss.IndexFlatL2(dimension)
            self._initialized = True
            print(f"📏 Índice inicializado con dimensión: {dimension}")
    
    def get_embedding(self, text: str, client) -> List[float]:
        """Genera el embedding para un texto usando Azure OpenAI o Foundry."""
        if self.config.get('use_foundry'):
            # Para Foundry, necesitamos usar el cliente de embeddings específico
            # Por ahora, usaremos el cliente OpenAI ya que Foundry usa la misma API
            if hasattr(client, 'embeddings'):
                response = client.embeddings.create(
                    model=self.config['embedding_deployment'],
                    input=text
                )
            else:
                # Si es el cliente de Foundry ChatCompletions, crear uno de OpenAI para embeddings
                openai_client = AzureOpenAI(
                    azure_endpoint=self.config['endpoint'].replace('/api/projects/myFirstProject', ''),
                    api_key=self.config['api_key'],
                    api_version="2024-02-01"
                )
                response = openai_client.embeddings.create(
                    model=self.config['embedding_deployment'],
                    input=text
                )
        else:
            response = client.embeddings.create(
                model=self.config['embedding_deployment'],
                input=text
            )
        
        embedding = response.data[0].embedding
        
        # Inicializar el índice si es necesario
        if not self._initialized:
            self._initialize_index(len(embedding))
            
        return embedding
    
    def cosine_similarity(self, vec1: np.ndarray, vec2: np.ndarray) -> float:
        """Calcula la similitud del coseno entre dos vectores."""
        vec1 = vec1.flatten()
        vec2 = vec2.flatten()
        dot_product = np.dot(vec1, vec2)
        norm1 = np.linalg.norm(vec1)
        norm2 = np.linalg.norm(vec2)
        return dot_product / (norm1 * norm2)
    
    def search(self, query_embedding: List[float], k: int = 5) -> Tuple[List[float], List[int]]:
        """Busca los k embeddings más similares en el índice."""
        query_vector = np.array([query_embedding]).astype('float32')
        distances, indices = self.index.search(query_vector, min(k, self.index.ntotal))
        
        # Convertir distancias L2 a similitudes del coseno
        similarities = []
        for i, idx in enumerate(indices[0]):
            if idx != -1:  # FAISS retorna -1 para resultados no válidos
                stored_embedding = self.index.reconstruct(int(idx))
                similarity = self.cosine_similarity(query_vector, stored_embedding)
                similarities.append(similarity)
            else:
                similarities.append(0.0)
                
        return similarities, indices[0].tolist()
    
    def get(self, prompt: str, client) -> Optional[str]:
        """Busca una respuesta en caché para el prompt dado."""
        if not self._initialized or self.index.ntotal == 0:
            self.cache_misses += 1
            return None
            
        # Generar embedding del prompt
        prompt_embedding = self.get_embedding(prompt, client)
        
        # Buscar los más similares
        similarities, indices = self.search(prompt_embedding, k=1)
        
        if similarities and similarities[0] > SIMILARITY_THRESHOLD:
            # Hit de caché
            self.cache_hits += 1
            cache_entry = self.cache[indices[0]]
            print(f"\n✅ CACHE HIT! Similitud: {similarities[0]:.4f}")
            print(f"   Prompt original: {cache_entry['prompt'][:50]}...")
            return cache_entry['response']
        
        # Miss de caché
        self.cache_misses += 1
        return None
    
    def put(self, prompt: str, response: str, client):
        """Almacena una respuesta en caché."""
        # Generar embedding
        embedding = self.get_embedding(prompt, client)
        embedding_vector = np.array([embedding]).astype('float32')
        
        # Añadir al índice FAISS
        idx = self.index.ntotal
        self.index.add(embedding_vector)
        
        # Almacenar en el diccionario de caché
        self.cache[idx] = {
            'prompt': prompt,
            'response': response,
            'timestamp': datetime.now().isoformat(),
            'embedding': embedding
        }
        
        print(f"💾 Respuesta almacenada en caché (índice: {idx})")
    
    def save(self):
        """Guarda la caché y el índice en disco."""
        # Guardar el índice FAISS
        faiss.write_index(self.index, INDEX_FILE)
        
        # Guardar el diccionario de caché
        with open(CACHE_FILE, 'wb') as f:
            pickle.dump(self.cache, f)
            
        print(f"💾 Caché guardada: {self.index.ntotal} entradas")
    
    def load(self):
        """Carga la caché y el índice desde disco."""
        try:
            # Verificar si ambos archivos existen
            if not os.path.exists(INDEX_FILE) or not os.path.exists(CACHE_FILE):
                print("⚠️  No se encontró caché previa - iniciando nueva caché")
                return False
                
            # Cargar el índice FAISS
            self.index = faiss.read_index(INDEX_FILE)
            self._initialized = True
            self.embedding_dimension = self.index.d
            
            # Cargar el diccionario de caché
            with open(CACHE_FILE, 'rb') as f:
                self.cache = pickle.load(f)
                
            print(f"📂 Caché cargada: {self.index.ntotal} entradas (dimensión: {self.embedding_dimension})")
            return True
        except Exception as e:
            print(f"⚠️  Error al cargar caché: {e}")
            print("   Iniciando nueva caché...")
            return False
    
    def get_stats(self) -> Dict:
        """Retorna estadísticas de la caché."""
        total_requests = self.cache_hits + self.cache_misses
        hit_rate = self.cache_hits / total_requests if total_requests > 0 else 0
        
        return {
            'total_entries': self.index.ntotal,
            'cache_hits': self.cache_hits,
            'cache_misses': self.cache_misses,
            'hit_rate': hit_rate,
            'total_requests': total_requests
        }

def call_gpt_with_cache(prompt: str, client, cache: SemanticCache, config: Dict) -> str:
    """Llama a GPT con caché semántica."""
    # Buscar en caché
    cached_response = cache.get(prompt, client)
    
    if cached_response:
        return cached_response
    
    # Si no está en caché, llamar a GPT
    print("🤖 Llamando a GPT-4...")
    start_time = time.time()
    
    if config.get('use_foundry'):
        # Usar Azure AI Foundry SDK
        response = client.complete(
            messages=[
                SystemMessage(content="Eres un asistente útil."),
                UserMessage(content=prompt)
            ],
            temperature=0.7,
            max_tokens=500,
            model=config['gpt_deployment']
        )
        result = response.choices[0].message.content
    else:
        # Usar Azure OpenAI SDK
        response = client.chat.completions.create(
            model=config['gpt_deployment'],
            messages=[
                {"role": "system", "content": "Eres un asistente útil."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.7,
            max_tokens=500
        )
        result = response.choices[0].message.content
    
    elapsed_time = time.time() - start_time
    print(f"⏱️  Tiempo de respuesta: {elapsed_time:.2f}s")
    
    # Almacenar en caché
    cache.put(prompt, result, client)
    
    return result

def create_client(config: Dict):
    """Crea el cliente apropiado según la configuración."""
    if config.get('use_foundry'):
        print("🏭 Usando Azure AI Foundry SDK")
        # Cliente para chat - usando el endpoint base sin el modelo en la URL
        chat_client = ChatCompletionsClient(
            endpoint=config['endpoint'],
            credential=AzureKeyCredential(config['api_key'])
        )
        # Cliente para embeddings (usando OpenAI SDK porque Foundry usa la misma API)
        # Extraer el endpoint base de OpenAI
        openai_endpoint = config['endpoint'].replace('services.ai.azure.com/api/projects/myFirstProject', 'openai.azure.com')
        embedding_client = AzureOpenAI(
            azure_endpoint=openai_endpoint,
            api_key=config['api_key'],
            api_version="2024-02-01"
        )
        return chat_client, embedding_client
    else:
        print("🔷 Usando Azure OpenAI SDK")
        client = AzureOpenAI(
            azure_endpoint=config['endpoint'],
            api_key=config['api_key'],
            api_version=config['api_version']
        )
        return client, client

def run_tests():
    """Ejecuta pruebas de la caché semántica."""
    # Obtener configuración
    config = get_parameters()
    
    print("\n🚀 Iniciando pruebas de caché semántica...")
    print(f"📍 Endpoint: {config['endpoint']}")
    print(f"🤖 GPT Deployment: {config['gpt_deployment']}")
    print(f"📊 Embedding Deployment: {config['embedding_deployment']}")
    print(f"🎯 Umbral de similitud: {SIMILARITY_THRESHOLD}")
    print("-" * 50)
    
    # Inicializar cliente
    chat_client, embedding_client = create_client(config)
    
    # Inicializar caché
    cache = SemanticCache(config=config)
    cache.load()  # Intentar cargar caché existente
    
    # Conjunto de pruebas con prompts similares
    test_prompts = [
        # Grupo 1: Preguntas sobre Python
        "¿Cuáles son las mejores prácticas para escribir código Python?",
        "¿Qué son las best practices para programar en Python?",
        "Dame las mejores prácticas de Python",
        
        # Grupo 2: Preguntas sobre IA
        "¿Qué es el aprendizaje automático?",
        "Explícame qué es machine learning",
        "¿Puedes explicar el aprendizaje automático?",
        
        # Grupo 3: Preguntas diferentes
        "¿Cuál es la capital de Francia?",
        "¿Cómo se hace una pizza margherita?",
        "¿Cuáles son los beneficios del ejercicio?",
        
        # Repetir algunas para probar caché
        "¿Cuáles son las mejores prácticas para escribir código Python?",
        "¿Qué es el aprendizaje automático?",
    ]
    
    print("\n🧪 EJECUTANDO PRUEBAS:\n")
    
    for i, prompt in enumerate(test_prompts, 1):
        print(f"\n{'='*60}")
        print(f"Prueba {i}/{len(test_prompts)}")
        print(f"Prompt: {prompt}")
        print("-" * 60)
        
        start_time = time.time()
        
        # Usar el cliente apropiado
        if config.get('use_foundry'):
            response = call_gpt_with_cache(prompt, chat_client, cache, config)
        else:
            response = call_gpt_with_cache(prompt, chat_client, cache, config)
        
        total_time = time.time() - start_time
        
        print(f"\nRespuesta: {response[:200]}...")
        print(f"⏱️  Tiempo total: {total_time:.2f}s")
        
        # Mostrar estadísticas actuales
        stats = cache.get_stats()
        print(f"\n📊 Estadísticas actuales:")
        print(f"   - Entradas en caché: {stats['total_entries']}")
        print(f"   - Cache hits: {stats['cache_hits']}")
        print(f"   - Cache misses: {stats['cache_misses']}")
        print(f"   - Hit rate: {stats['hit_rate']:.2%}")
    
    # Guardar caché
    cache.save()
    
    # Resumen final
    print(f"\n{'='*60}")
    print("📈 RESUMEN FINAL:")
    final_stats = cache.get_stats()
    print(f"   - Total de consultas: {final_stats['total_requests']}")
    print(f"   - Cache hits: {final_stats['cache_hits']}")
    print(f"   - Cache misses: {final_stats['cache_misses']}")
    print(f"   - Hit rate final: {final_stats['hit_rate']:.2%}")
    print(f"   - Entradas en caché: {final_stats['total_entries']}")
    
    # Prueba adicional: buscar similitudes
    print(f"\n{'='*60}")
    print("🔍 ANÁLISIS DE SIMILITUDES:\n")
    
    test_query = "¿Cuáles son las buenas prácticas de programación en Python?"
    print(f"Query de prueba: {test_query}")
    
    # Usar el cliente de embeddings
    query_embedding = cache.get_embedding(test_query, embedding_client)
    similarities, indices = cache.search(query_embedding, k=5)
    
    print("\nTop 5 entradas más similares:")
    for i, (sim, idx) in enumerate(zip(similarities, indices)):
        if idx != -1 and idx in cache.cache:
            entry = cache.cache[idx]
            print(f"\n{i+1}. Similitud: {sim:.4f}")
            print(f"   Prompt: {entry['prompt']}")
            print(f"   Timestamp: {entry['timestamp']}")

if __name__ == "__main__":
    try:
        run_tests()
    except KeyboardInterrupt:
        print("\n\n⚠️  Prueba interrumpida por el usuario")
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()