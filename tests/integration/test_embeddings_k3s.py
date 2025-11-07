"""
Integration tests for BGE-M3 Embedding Service on K3s
Tests the deployed embedding service via port-forward
"""

import subprocess
import time
import signal
import os
import requests
import pytest
from typing import Optional


class PortForwardManager:
    """Context manager for kubectl port-forward"""

    def __init__(self, namespace: str, service: str, local_port: int, remote_port: int):
        self.namespace = namespace
        self.service = service
        self.local_port = local_port
        self.remote_port = remote_port
        self.process: Optional[subprocess.Popen] = None

    def __enter__(self):
        """Start port-forward"""
        cmd = [
            "kubectl", "port-forward",
            f"svc/{self.service}",
            f"{self.local_port}:{self.remote_port}",
            "-n", self.namespace
        ]

        self.process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            preexec_fn=os.setsid
        )

        # Wait for port-forward to be ready
        time.sleep(3)

        # Check if process is still running
        if self.process.poll() is not None:
            raise RuntimeError(f"Port-forward failed to start: {self.process.stderr.read().decode()}")

        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Stop port-forward"""
        if self.process:
            try:
                # Kill the entire process group
                os.killpg(os.getpgid(self.process.pid), signal.SIGTERM)
                self.process.wait(timeout=5)
            except Exception as e:
                print(f"Warning: Error stopping port-forward: {e}")

    @property
    def base_url(self) -> str:
        """Get the base URL for the service"""
        return f"http://localhost:{self.local_port}"


@pytest.fixture(scope="module")
def embeddings_service():
    """Fixture to set up port-forward to embeddings service"""
    namespace = os.environ.get("NAMESPACE", "transcript-pipeline")
    service = os.environ.get("SERVICE", "embeddings")
    local_port = int(os.environ.get("LOCAL_PORT", "8001"))
    remote_port = 8001

    with PortForwardManager(namespace, service, local_port, remote_port) as pf:
        # Wait a bit more to ensure service is ready
        time.sleep(2)
        yield pf.base_url


class TestEmbeddingsHealth:
    """Tests for the health endpoint"""

    def test_health_endpoint_returns_200(self, embeddings_service):
        """Test that health endpoint returns 200 OK"""
        response = requests.get(f"{embeddings_service}/health", timeout=10)
        assert response.status_code == 200

    def test_health_endpoint_schema(self, embeddings_service):
        """Test that health endpoint returns correct schema"""
        response = requests.get(f"{embeddings_service}/health", timeout=10)
        data = response.json()

        # Check required fields
        assert "status" in data
        assert "model" in data
        assert "gpu_memory_gb" in data
        assert "uptime_seconds" in data

        # Check field types
        assert isinstance(data["status"], str)
        assert isinstance(data["model"], str)
        assert isinstance(data["gpu_memory_gb"], (int, float))
        assert isinstance(data["uptime_seconds"], int)

        # Check field values
        assert data["status"] == "healthy"
        assert data["model"] == "BAAI/bge-m3"
        assert data["gpu_memory_gb"] >= 0
        assert data["uptime_seconds"] >= 0


class TestEmbeddingsGeneration:
    """Tests for embedding generation"""

    def test_single_text_embedding(self, embeddings_service):
        """Test generating embedding for a single text"""
        response = requests.post(
            f"{embeddings_service}/embed/batch",
            json={"texts": ["Hello, world!"]},
            headers={"Content-Type": "application/json"},
            timeout=30
        )

        assert response.status_code == 200
        data = response.json()

        # Check response structure
        assert "embeddings" in data
        assert "processing_time_ms" in data
        assert "batch_size" in data
        assert "model" in data

        # Check embedding properties
        assert len(data["embeddings"]) == 1
        assert len(data["embeddings"][0]) == 1024  # BGE-M3 produces 1024-dim vectors
        assert data["batch_size"] == 1
        assert data["model"] == "BAAI/bge-m3"
        assert data["processing_time_ms"] > 0

        # Check that embeddings are floats
        assert all(isinstance(x, float) for x in data["embeddings"][0])

    def test_batch_embedding(self, embeddings_service):
        """Test generating embeddings for multiple texts"""
        texts = [
            "The quick brown fox jumps over the lazy dog.",
            "Machine learning is a subset of artificial intelligence.",
            "Python is a popular programming language.",
            "Natural language processing enables computers to understand human language.",
            "Deep learning models require large amounts of data.",
            "Embeddings represent text as dense vectors.",
            "GPUs accelerate neural network training.",
            "Transformers revolutionized NLP tasks."
        ]

        response = requests.post(
            f"{embeddings_service}/embed/batch",
            json={"texts": texts},
            headers={"Content-Type": "application/json"},
            timeout=30
        )

        assert response.status_code == 200
        data = response.json()

        # Check response structure
        assert len(data["embeddings"]) == len(texts)
        assert data["batch_size"] == len(texts)

        # Check all embeddings have correct dimension
        for embedding in data["embeddings"]:
            assert len(embedding) == 1024
            assert all(isinstance(x, float) for x in embedding)

    def test_embedding_consistency(self, embeddings_service):
        """Test that same text produces similar embeddings"""
        text = "Consistency test for embeddings"

        # Generate embedding twice
        response1 = requests.post(
            f"{embeddings_service}/embed/batch",
            json={"texts": [text]},
            timeout=30
        )
        response2 = requests.post(
            f"{embeddings_service}/embed/batch",
            json={"texts": [text]},
            timeout=30
        )

        assert response1.status_code == 200
        assert response2.status_code == 200

        embedding1 = response1.json()["embeddings"][0]
        embedding2 = response2.json()["embeddings"][0]

        # Embeddings should be identical (deterministic)
        assert embedding1 == embedding2


class TestEmbeddingsValidation:
    """Tests for input validation"""

    def test_empty_texts_list_returns_400(self, embeddings_service):
        """Test that empty texts list returns 400"""
        response = requests.post(
            f"{embeddings_service}/embed/batch",
            json={"texts": []},
            headers={"Content-Type": "application/json"},
            timeout=10
        )

        assert response.status_code == 422  # FastAPI validation error

    def test_oversized_batch_returns_400(self, embeddings_service):
        """Test that batch size > 32 returns 400"""
        texts = [f"Text {i}" for i in range(33)]

        response = requests.post(
            f"{embeddings_service}/embed/batch",
            json={"texts": texts},
            headers={"Content-Type": "application/json"},
            timeout=10
        )

        assert response.status_code == 422  # FastAPI validation error

    def test_empty_string_returns_400(self, embeddings_service):
        """Test that empty string in texts returns 400"""
        response = requests.post(
            f"{embeddings_service}/embed/batch",
            json={"texts": [""]},
            headers={"Content-Type": "application/json"},
            timeout=10
        )

        assert response.status_code == 422  # FastAPI validation error

    def test_whitespace_only_returns_400(self, embeddings_service):
        """Test that whitespace-only string returns 400"""
        response = requests.post(
            f"{embeddings_service}/embed/batch",
            json={"texts": ["   "]},
            headers={"Content-Type": "application/json"},
            timeout=10
        )

        assert response.status_code == 422  # FastAPI validation error


class TestEmbeddingsPerformance:
    """Tests for performance characteristics"""

    def test_latency_single_text(self, embeddings_service):
        """Test that latency is reasonable for single text"""
        start_time = time.time()

        response = requests.post(
            f"{embeddings_service}/embed/batch",
            json={"texts": ["Performance test text"]},
            timeout=30
        )

        elapsed_ms = (time.time() - start_time) * 1000

        assert response.status_code == 200
        # Should be under 100ms per text on T4 GPU (generous threshold)
        assert elapsed_ms < 1000  # 1 second for single text

        # Check reported processing time
        processing_time = response.json()["processing_time_ms"]
        assert processing_time < 1000

    def test_latency_batch(self, embeddings_service):
        """Test that batch processing is efficient"""
        texts = [f"Batch performance test {i}" for i in range(10)]

        start_time = time.time()

        response = requests.post(
            f"{embeddings_service}/embed/batch",
            json={"texts": texts},
            timeout=30
        )

        elapsed_ms = (time.time() - start_time) * 1000
        per_text_ms = elapsed_ms / len(texts)

        assert response.status_code == 200
        # Batch should be more efficient than 100ms per text
        assert per_text_ms < 100


class TestMetricsEndpoint:
    """Tests for Prometheus metrics endpoint"""

    def test_metrics_endpoint_exists(self, embeddings_service):
        """Test that metrics endpoint is accessible"""
        response = requests.get(f"{embeddings_service}/metrics", timeout=10)
        assert response.status_code == 200

    def test_metrics_format(self, embeddings_service):
        """Test that metrics are in Prometheus format"""
        response = requests.get(f"{embeddings_service}/metrics", timeout=10)
        assert response.status_code == 200

        content = response.text

        # Check for expected metrics
        assert "embeddings_requests_total" in content
        assert "embeddings_latency_seconds" in content
        assert "embeddings_batch_size" in content
        assert "gpu_memory_used_bytes" in content


if __name__ == "__main__":
    # Run tests with pytest
    pytest.main([__file__, "-v", "--tb=short"])
