import os
import time
import json
import hashlib
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Tuple, Union
import numpy as np
from openai import AzureOpenAI
from azure.ai.inference import EmbeddingsClient
from azure.core.credentials import AzureKeyCredential
from azure.identity import DefaultAzureCredential
import faiss
import pickle
import logging
from dataclasses import dataclass, field
from enum import Enum
import asyncio
from concurrent.futures import ThreadPoolExecutor

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Configuration constants
CACHE_FILE = "embedding_cache.pkl"
INDEX_FILE = "embedding_index.faiss"
BATCH_CACHE_FILE = "embedding_batch_cache.pkl"

class InputType(Enum):
    """Types of embedding inputs as per OpenAI API"""
    QUERY = "query"
    DOCUMENT = "document"
    PASSAGE = "passage"
    
class EncodingFormat(Enum):
    """Encoding formats for embeddings"""
    FLOAT = "float"
    BASE64 = "base64"

@dataclass
class EmbeddingCacheConfig:
    """Configuration optimized for embedding caching"""
    endpoint: str
    api_key: Optional[str] = None
    use_managed_identity: bool = False
    embedding_deployment: str = "text-embedding-3-large"
    api_version: str = "2024-02-01"
    
    # Embedding-specific settings
    default_dimensions: int = 3072  # text-embedding-3-large default
    similarity_threshold_embeddings: float = 0.95  # High threshold for exact matches
    similarity_threshold_other: float = 0.10  # Lower for semantic similarity
    
    # Cache TTL settings (in hours)
    ttl_query_embeddings: int = 168  # 7 days for queries
    ttl_document_embeddings: int = 336  # 14 days for documents
    ttl_passage_embeddings: int = 336  # 14 days for passages
    ttl_other: int = 24  # 1 day for other operations
    
    # Performance settings
    batch_size: int = 100  # Max batch size for embeddings
    max_cache_size_gb: float = 10.0  # Maximum cache size
    enable_compression: bool = True  # Compress cached embeddings
    
    @classmethod
    def from_environment(cls):
        """Create configuration from environment variables"""
        return cls(
            endpoint=os.environ.get("AZURE_OPENAI_ENDPOINT", ""),
            api_key=os.environ.get("AZURE_OPENAI_KEY"),
            use_managed_identity=os.environ.get("USE_MANAGED_IDENTITY", "false").lower() == "true",
            embedding_deployment=os.environ.get("EMBEDDING_DEPLOYMENT", "text-embedding-3-large"),
            api_version=os.environ.get("API_VERSION", "2024-02-01"),
            default_dimensions=int(os.environ.get("EMBEDDING_DIMENSIONS", "3072")),
            batch_size=int(os.environ.get("EMBEDDING_BATCH_SIZE", "100"))
        )

@dataclass
class EmbeddingRequest:
    """Structured embedding request"""
    input: Union[str, List[str]]
    input_type: InputType = InputType.QUERY
    dimensions: Optional[int] = None
    encoding_format: EncodingFormat = EncodingFormat.FLOAT
    user: Optional[str] = None
    metadata: Optional[Dict] = None
    
    def cache_key(self) -> str:
        """Generate a unique cache key for this request"""
        key_parts = []
        
        # Handle single or batch input
        if isinstance(self.input, str):
            key_parts.append(hashlib.sha256(self.input.encode()).hexdigest()[:16])
        else:
            # For batch, create hash of all inputs
            batch_hash = hashlib.sha256(
                "|".join(self.input).encode()
            ).hexdigest()[:16]
            key_parts.append(f"batch_{len(self.input)}_{batch_hash}")
        
        key_parts.extend([
            self.input_type.value,
            str(self.dimensions or "default"),
            self.encoding_format.value,
            self.user or "anonymous"
        ])
        
        if self.metadata:
            metadata_hash = hashlib.sha256(
                json.dumps(self.metadata, sort_keys=True).encode()
            ).hexdigest()[:8]
            key_parts.append(metadata_hash)
        
        return "|".join(key_parts)

class EmbeddingSemanticCache:
    """Semantic cache optimized for embedding operations"""
    
    def __init__(self, config: EmbeddingCacheConfig):
        self.config = config
        self.embedding_dimension = config.default_dimensions
        self.index = None
        self.cache: Dict[str, Dict] = {}  # Using string keys for better tracking
        self.batch_cache: Dict[str, List[List[float]]] = {}  # Cache for batch embeddings
        self.stats = {
            "embedding_hits": 0,
            "embedding_misses": 0,
            "batch_hits": 0,
            "batch_misses": 0,
            "other_hits": 0,
            "other_misses": 0,
            "total_tokens_saved": 0
        }
        self._initialized = False
        self.executor = ThreadPoolExecutor(max_workers=4)
        
    def _initialize_index(self, dimension: int):
        """Initialize FAISS index optimized for embeddings"""
        if not self._initialized:
            self.embedding_dimension = dimension
            
            # Use IVF index for better performance with large datasets
            if self.cache and len(self.cache) > 10000:
                # For large datasets, use IVF with PQ compression
                nlist = int(np.sqrt(len(self.cache)))
                quantizer = faiss.IndexFlatL2(dimension)
                self.index = faiss.IndexIVFPQ(quantizer, dimension, nlist, 16, 8)
            else:
                # For smaller datasets, use flat index
                self.index = faiss.IndexFlatL2(dimension)
                
            self._initialized = True
            logger.info(f"Index initialized for embeddings (dimension: {dimension})")
    
    def estimate_tokens(self, text: Union[str, List[str]]) -> int:
        """Estimate token count for text"""
        if isinstance(text, str):
            # Rough estimate: 1 token per 4 characters
            return len(text) // 4
        else:
            return sum(len(t) // 4 for t in text)
    
    def get_ttl_hours(self, input_type: InputType) -> int:
        """Get TTL based on input type"""
        ttl_map = {
            InputType.QUERY: self.config.ttl_query_embeddings,
            InputType.DOCUMENT: self.config.ttl_document_embeddings,
            InputType.PASSAGE: self.config.ttl_passage_embeddings
        }
        return ttl_map.get(input_type, self.config.ttl_other)
    
    def is_cache_entry_valid(self, entry: Dict, input_type: InputType) -> bool:
        """Check if cache entry is still valid"""
        if 'timestamp' not in entry:
            return True
            
        entry_time = datetime.fromisoformat(entry['timestamp'])
        ttl_hours = self.get_ttl_hours(input_type)
        age_hours = (datetime.now() - entry_time).total_seconds() / 3600
        
        return age_hours < ttl_hours
    
    async def get_embedding_async(self, request: EmbeddingRequest, client) -> Optional[Union[List[float], List[List[float]]]]:
        """Async method to get embeddings with caching"""
        cache_key = request.cache_key()
        
        # Check if it's a batch request
        is_batch = isinstance(request.input, list)
        
        # Check cache
        if is_batch and cache_key in self.batch_cache:
            self.stats["batch_hits"] += 1
            logger.info(f"Batch cache hit for {len(request.input)} inputs")
            return self.batch_cache[cache_key]
        elif not is_batch and cache_key in self.cache:
            entry = self.cache[cache_key]
            if self.is_cache_entry_valid(entry, request.input_type):
                self.stats["embedding_hits"] += 1
                self.stats["total_tokens_saved"] += self.estimate_tokens(request.input)
                logger.info(f"Embedding cache hit (type: {request.input_type.value})")
                return entry['embedding']
        
        # Cache miss - need to call API
        return None
    
    def get_embedding(self, request: EmbeddingRequest, client) -> Union[List[float], List[List[float]]]:
        """Get embeddings with caching (sync wrapper)"""
        # Try cache first
        loop = asyncio.new_event_loop()
        cached = loop.run_until_complete(self.get_embedding_async(request, client))
        if cached is not None:
            return cached
        
        # Cache miss - call API
        try:
            logger.info(f"Calling embedding API (type: {request.input_type.value})")
            start_time = time.time()
            
            # Prepare API call parameters
            params = {
                "model": self.config.embedding_deployment,
                "input": request.input
            }
            
            # Add optional parameters
            if request.dimensions:
                params["dimensions"] = request.dimensions
            if request.user:
                params["user"] = request.user
            if request.encoding_format == EncodingFormat.BASE64:
                params["encoding_format"] = "base64"
                
            # Call API
            response = client.embeddings.create(**params)
            
            elapsed = time.time() - start_time
            logger.info(f"Embedding API call completed in {elapsed:.2f}s")
            
            # Extract embeddings
            if isinstance(request.input, str):
                embedding = response.data[0].embedding
                self.stats["embedding_misses"] += 1
                
                # Initialize index if needed
                if not self._initialized:
                    self._initialize_index(len(embedding))
                
                # Cache the result
                self._cache_single_embedding(request, embedding)
                
                return embedding
            else:
                # Batch embeddings
                embeddings = [item.embedding for item in response.data]
                self.stats["batch_misses"] += 1
                
                # Initialize index if needed
                if not self._initialized and embeddings:
                    self._initialize_index(len(embeddings[0]))
                
                # Cache batch result
                self._cache_batch_embeddings(request, embeddings)
                
                return embeddings
                
        except Exception as e:
            logger.error(f"Error getting embeddings: {e}")
            raise
    
    def _cache_single_embedding(self, request: EmbeddingRequest, embedding: List[float]):
        """Cache a single embedding"""
        cache_key = request.cache_key()
        
        # Store in cache
        self.cache[cache_key] = {
            'input': request.input,
            'input_type': request.input_type.value,
            'embedding': embedding,
            'dimensions': len(embedding),
            'timestamp': datetime.now().isoformat(),
            'user': request.user,
            'metadata': request.metadata
        }
        
        # Add to FAISS index if initialized
        if self.index is not None:
            embedding_vector = np.array([embedding]).astype('float32')
            self.index.add(embedding_vector)
        
        logger.info(f"Cached embedding (key: {cache_key[:20]}...)")
    
    def _cache_batch_embeddings(self, request: EmbeddingRequest, embeddings: List[List[float]]):
        """Cache batch embeddings"""
        cache_key = request.cache_key()
        
        # Store batch in batch cache
        self.batch_cache[cache_key] = embeddings
        
        # Also store individual embeddings for future single queries
        if isinstance(request.input, list):
            for i, (text, embedding) in enumerate(zip(request.input, embeddings)):
                single_request = EmbeddingRequest(
                    input=text,
                    input_type=request.input_type,
                    dimensions=request.dimensions,
                    encoding_format=request.encoding_format,
                    user=request.user,
                    metadata=request.metadata
                )
                self._cache_single_embedding(single_request, embedding)
        
        logger.info(f"Cached batch of {len(embeddings)} embeddings")
    
    def search_similar(self, query_embedding: List[float], k: int = 5, threshold: float = None) -> List[Tuple[str, float, Dict]]:
        """Search for similar embeddings in cache"""
        if not self.index or self.index.ntotal == 0:
            return []
        
        if threshold is None:
            threshold = self.config.similarity_threshold_embeddings
        
        query_vector = np.array([query_embedding]).astype('float32')
        distances, indices = self.index.search(query_vector, min(k, self.index.ntotal))
        
        results = []
        for dist, idx in zip(distances[0], indices[0]):
            if idx == -1:
                continue
                
            # Calculate cosine similarity from L2 distance
            similarity = 1 - (dist / 2)  # Approximate conversion
            
            if similarity >= threshold:
                # Find the cache entry
                for cache_key, entry in self.cache.items():
                    # Match by checking if embeddings are close enough
                    if 'embedding' in entry:
                        cached_emb = np.array(entry['embedding'])
                        if np.allclose(cached_emb, self.index.reconstruct(int(idx)), atol=1e-5):
                            results.append((cache_key, similarity, entry))
                            break
        
        return results
    
    def get_stats_detailed(self) -> Dict:
        """Get detailed statistics"""
        total_embedding_requests = self.stats["embedding_hits"] + self.stats["embedding_misses"]
        total_batch_requests = self.stats["batch_hits"] + self.stats["batch_misses"]
        
        embedding_hit_rate = (
            self.stats["embedding_hits"] / total_embedding_requests 
            if total_embedding_requests > 0 else 0
        )
        batch_hit_rate = (
            self.stats["batch_hits"] / total_batch_requests 
            if total_batch_requests > 0 else 0
        )
        
        # Calculate cache size
        cache_size_mb = 0
        if os.path.exists(CACHE_FILE):
            cache_size_mb += os.path.getsize(CACHE_FILE) / (1024 * 1024)
        if os.path.exists(INDEX_FILE):
            cache_size_mb += os.path.getsize(INDEX_FILE) / (1024 * 1024)
        if os.path.exists(BATCH_CACHE_FILE):
            cache_size_mb += os.path.getsize(BATCH_CACHE_FILE) / (1024 * 1024)
        
        # Estimate cost savings (rough estimate)
        tokens_saved = self.stats["total_tokens_saved"]
        cost_per_1k_tokens = 0.0001  # text-embedding-3-large pricing
        cost_saved = (tokens_saved / 1000) * cost_per_1k_tokens
        
        return {
            'embedding_stats': {
                'hits': self.stats["embedding_hits"],
                'misses': self.stats["embedding_misses"],
                'hit_rate': f"{embedding_hit_rate:.2%}",
                'total_requests': total_embedding_requests
            },
            'batch_stats': {
                'hits': self.stats["batch_hits"],
                'misses': self.stats["batch_misses"],
                'hit_rate': f"{batch_hit_rate:.2%}",
                'total_requests': total_batch_requests
            },
            'cache_info': {
                'total_entries': len(self.cache),
                'batch_entries': len(self.batch_cache),
                'index_size': self.index.ntotal if self.index else 0,
                'cache_size_mb': round(cache_size_mb, 2),
                'dimensions': self.embedding_dimension
            },
            'performance': {
                'tokens_saved': tokens_saved,
                'estimated_cost_saved': f"${cost_saved:.4f}",
                'avg_embedding_size': self.embedding_dimension * 4 / 1024,  # KB per embedding
            }
        }
    
    def save(self):
        """Save cache to disk"""
        try:
            # Save FAISS index
            if self.index:
                faiss.write_index(self.index, INDEX_FILE)
            
            # Save cache dictionaries
            with open(CACHE_FILE, 'wb') as f:
                pickle.dump(self.cache, f)
            
            with open(BATCH_CACHE_FILE, 'wb') as f:
                pickle.dump(self.batch_cache, f)
            
            logger.info(f"Cache saved: {len(self.cache)} single + {len(self.batch_cache)} batch entries")
            
        except Exception as e:
            logger.error(f"Error saving cache: {e}")
    
    def load(self) -> bool:
        """Load cache from disk"""
        try:
            loaded_any = False
            
            # Load FAISS index
            if os.path.exists(INDEX_FILE):
                self.index = faiss.read_index(INDEX_FILE)
                self._initialized = True
                self.embedding_dimension = self.index.d
                loaded_any = True
            
            # Load cache dictionary
            if os.path.exists(CACHE_FILE):
                with open(CACHE_FILE, 'rb') as f:
                    self.cache = pickle.load(f)
                loaded_any = True
            
            # Load batch cache
            if os.path.exists(BATCH_CACHE_FILE):
                with open(BATCH_CACHE_FILE, 'rb') as f:
                    self.batch_cache = pickle.load(f)
                loaded_any = True
            
            if loaded_any:
                logger.info(f"Cache loaded: {len(self.cache)} single + {len(self.batch_cache)} batch entries")
            else:
                logger.info("No existing cache found")
                
            return loaded_any
            
        except Exception as e:
            logger.error(f"Error loading cache: {e}")
            return False
    
    def cleanup_expired(self):
        """Clean up expired cache entries"""
        expired_keys = []
        
        for key, entry in self.cache.items():
            input_type = InputType(entry.get('input_type', 'query'))
            if not self.is_cache_entry_valid(entry, input_type):
                expired_keys.append(key)
        
        if expired_keys:
            logger.info(f"Removing {len(expired_keys)} expired entries")
            for key in expired_keys:
                del self.cache[key]
            
            # Note: Rebuilding FAISS index after cleanup is complex
            # In production, consider periodic full rebuilds

def create_embedding_client(config: EmbeddingCacheConfig):
    """Create embedding client"""
    if config.use_managed_identity:
        credential = DefaultAzureCredential()
        return AzureOpenAI(
            azure_endpoint=config.endpoint,
            azure_ad_token_provider=lambda: credential.get_token("https://cognitiveservices.azure.com/.default").token,
            api_version=config.api_version
        )
    else:
        return AzureOpenAI(
            azure_endpoint=config.endpoint,
            api_key=config.api_key,
            api_version=config.api_version
        )

def run_embedding_tests():
    """Run embedding-focused tests"""
    print("\n🚀 Embedding-Optimized Semantic Cache Test Suite")
    print("=" * 60)
    
    # Configuration
    config = EmbeddingCacheConfig.from_environment()
    
    if not config.endpoint:
        print("\n❌ Please set environment variables:")
        print("   export AZURE_OPENAI_ENDPOINT='your-endpoint'")
        print("   export AZURE_OPENAI_KEY='your-key'")
        print("   export EMBEDDING_DEPLOYMENT='text-embedding-3-large'")
        return
    
    print(f"\n📍 Configuration:")
    print(f"   Endpoint: {config.endpoint}")
    print(f"   Deployment: {config.embedding_deployment}")
    print(f"   Default Dimensions: {config.default_dimensions}")
    print(f"   TTL (Query/Document): {config.ttl_query_embeddings}h / {config.ttl_document_embeddings}h")
    print("-" * 60)
    
    # Initialize
    client = create_embedding_client(config)
    cache = EmbeddingSemanticCache(config)
    cache.load()
    
    # Test scenarios
    test_scenarios = [
        # Single embeddings - queries
        EmbeddingRequest(
            input="What is machine learning?",
            input_type=InputType.QUERY
        ),
        EmbeddingRequest(
            input="What is machine learning?",  # Exact duplicate
            input_type=InputType.QUERY
        ),
        EmbeddingRequest(
            input="Explain machine learning",  # Similar query
            input_type=InputType.QUERY
        ),
        
        # Single embeddings - documents
        EmbeddingRequest(
            input="Machine learning is a subset of artificial intelligence that enables systems to learn and improve from experience without being explicitly programmed.",
            input_type=InputType.DOCUMENT
        ),
        
        # Batch embeddings
        EmbeddingRequest(
            input=[
                "What is deep learning?",
                "How does neural network work?",
                "Explain backpropagation"
            ],
            input_type=InputType.QUERY
        ),
        
        # Same batch again (should hit cache)
        EmbeddingRequest(
            input=[
                "What is deep learning?",
                "How does neural network work?",
                "Explain backpropagation"
            ],
            input_type=InputType.QUERY
        ),
        
        # Embeddings with custom dimensions
        EmbeddingRequest(
            input="Custom dimension test",
            input_type=InputType.QUERY,
            dimensions=1536  # Smaller dimension
        ),
        
        # Document embeddings with metadata
        EmbeddingRequest(
            input="Advanced AI systems use transformer architectures for natural language processing.",
            input_type=InputType.DOCUMENT,
            user="test_user",
            metadata={"source": "ai_textbook", "chapter": 5}
        )
    ]
    
    print("\n🧪 Running Embedding Tests:\n")
    
    for i, request in enumerate(test_scenarios, 1):
        print(f"\n{'='*60}")
        print(f"Test {i}/{len(test_scenarios)}")
        
        if isinstance(request.input, str):
            print(f"Input: {request.input[:80]}...")
        else:
            print(f"Batch Input: {len(request.input)} items")
        
        print(f"Type: {request.input_type.value}")
        if request.dimensions:
            print(f"Dimensions: {request.dimensions}")
        print("-" * 60)
        
        start_time = time.time()
        
        try:
            result = cache.get_embedding(request, client)
            elapsed = time.time() - start_time
            
            if isinstance(result, list) and isinstance(result[0], float):
                print(f"✅ Single embedding received (dim: {len(result)})")
            else:
                print(f"✅ Batch of {len(result)} embeddings received")
            
            print(f"⏱️  Time: {elapsed:.3f}s")
            
            # Show current stats
            stats = cache.get_stats_detailed()
            print(f"\n📊 Embedding Stats:")
            print(f"   Single: {stats['embedding_stats']['hits']} hits / {stats['embedding_stats']['misses']} misses ({stats['embedding_stats']['hit_rate']})")
            print(f"   Batch: {stats['batch_stats']['hits']} hits / {stats['batch_stats']['misses']} misses ({stats['batch_stats']['hit_rate']})")
            print(f"   Tokens saved: {stats['performance']['tokens_saved']}")
            
        except Exception as e:
            logger.error(f"Test failed: {e}")
            continue
    
    # Save cache
    cache.save()
    
    # Final report
    print(f"\n{'='*60}")
    print("📈 FINAL REPORT:")
    print(f"{'='*60}")
    
    final_stats = cache.get_stats_detailed()
    
    print("\n📊 Embedding Performance:")
    for key, value in final_stats['embedding_stats'].items():
        print(f"   {key}: {value}")
    
    print("\n📦 Batch Performance:")
    for key, value in final_stats['batch_stats'].items():
        print(f"   {key}: {value}")
    
    print("\n💾 Cache Information:")
    for key, value in final_stats['cache_info'].items():
        print(f"   {key}: {value}")
    
    print("\n💰 Cost Savings:")
    for key, value in final_stats['performance'].items():
        print(f"   {key}: {value}")
    
    # Search demonstration
    print(f"\n🔍 Similarity Search Demo:")
    if cache.cache:
        # Get a sample embedding
        sample_key = list(cache.cache.keys())[0]
        sample_embedding = cache.cache[sample_key]['embedding']
        
        similar = cache.search_similar(sample_embedding, k=3)
        print(f"\nTop 3 similar to '{cache.cache[sample_key]['input'][:50]}...':")
        for i, (key, similarity, entry) in enumerate(similar, 1):
            print(f"{i}. Similarity: {similarity:.4f} - {entry['input'][:50]}...")

if __name__ == "__main__":
    try:
        run_embedding_tests()
    except KeyboardInterrupt:
        print("\n\n⚠️  Test interrupted")
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()