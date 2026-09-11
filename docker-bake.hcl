variable "LLAMA_TAG" {
  default = "v0.4.0"
}

variable "CUDA_ARCH" {
  default = "75" # Turing CC 7.5 for RTX 2070 Super
}

variable "CUDA_VERSION" {
  default = "12.4.1"
}

variable "UBUNTU_VERSION" {
  default = "22.04"
}

group "default" {
  targets = ["deb"]
}

# Target: Build and extract native .deb package directly to ./dist
target "deb" {
  target = "export-deb"
  output = ["type=local,dest=./dist"]
  args = {
    LLAMA_TAG = LLAMA_TAG
    CUDA_ARCH = CUDA_ARCH
    CUDA_VERSION = CUDA_VERSION
    UBUNTU_VERSION = UBUNTU_VERSION
  }
}

# Target: Build OCI container image
target "image" {
  target = "runtime"
  tags = [
    "llama-server-cuda:latest",
    "llama-server-cuda:${LLAMA_TAG}"
  ]
  args = {
    LLAMA_TAG = LLAMA_TAG
    CUDA_ARCH = CUDA_ARCH
    CUDA_VERSION = CUDA_VERSION
    UBUNTU_VERSION = UBUNTU_VERSION
  }
}
