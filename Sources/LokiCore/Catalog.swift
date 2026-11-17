import Foundation

/// Startkatalog: MLX-Modelle, die auf einem Mac mit 64 GB laufen. Keine feste Liste –
/// über „Modell hinzufügen“ lässt sich jedes MLX-Modell von Hugging Face laden.
///
/// Größen sind Schätzwerte; vor dem Download ermittelt LOKI die echte Größe aus der Dateiliste.
/// Qualitätswerte sind Startwerte je Aufgabenart und gelten als „geschätzt“, bis LOKI selbst misst.
public enum Catalog {
    private static let qwenAuthor = "Alibaba (Qwen)"
    private static let llama32 = LicenseInfo(
        name: "Llama 3.2 Community License", licenseClass: .conditions,
        note: "Hinweis „Built with Llama“ und Meta-Nutzungsrichtlinie. Die multimodalen Llama-Modelle schließen Personen und Firmen mit Sitz in der EU aus – dieses reine Textmodell nicht.")

    public static let models: [ModelDescriptor] = [
        ModelDescriptor(
            id: "mlx-community/Qwen3-4B-4bit", name: "Qwen3 4B", family: "Qwen", publisher: qwenAuthor,
            summary: "Klein und schnell. Gutes Startmodell für kurze Fragen und erste Tests.",
            totalParamsB: 4.0, activeParamsB: 4.0, approxBytes: 2_300_000_000, contextTokens: 32_768,
            capabilities: [.chat, .coding, .reasoning, .tools], license: .apache2,
            quality: [.quick: 0.62, .chat: 0.55, .writing: 0.50, .coding: 0.50, .reasoning: 0.55, .longContext: 0.30],
            supportsThinking: true),
        ModelDescriptor(
            id: "mlx-community/Qwen3-8B-4bit", name: "Qwen3 8B", family: "Qwen", publisher: qwenAuthor,
            summary: "Solider Allrounder mit wenig Speicherbedarf.",
            totalParamsB: 8.2, activeParamsB: 8.2, approxBytes: 4_600_000_000, contextTokens: 32_768,
            capabilities: [.chat, .coding, .reasoning, .tools], license: .apache2,
            quality: [.quick: 0.66, .chat: 0.62, .writing: 0.58, .coding: 0.58, .reasoning: 0.62, .longContext: 0.35],
            supportsThinking: true),
        ModelDescriptor(
            id: "mlx-community/gemma-4-e4b-it-4bit", name: "Gemma 4 E4B", family: "Gemma", publisher: "Google DeepMind",
            summary: "Kompaktes Gemma-4-Modell mit gutem Deutsch und langem Kontext.",
            totalParamsB: 8.0, activeParamsB: 4.5, approxBytes: 5_000_000_000, contextTokens: 131_072,
            capabilities: [.chat, .longContext], license: .apache2,
            quality: [.quick: 0.64, .chat: 0.62, .writing: 0.64, .coding: 0.50, .reasoning: 0.55, .longContext: 0.55]),
        ModelDescriptor(
            id: "mlx-community/gemma-4-26b-a4b-it-4bit", name: "Gemma 4 26B A4B", family: "Gemma", publisher: "Google DeepMind",
            summary: "Mixture of Experts mit nur 3,8B aktiven Parametern: schnell und stark bei Texten.",
            totalParamsB: 25.2, activeParamsB: 3.8, approxBytes: 15_600_000_000, contextTokens: 262_144,
            capabilities: [.chat, .coding, .reasoning, .tools, .longContext], license: .apache2,
            quality: [.quick: 0.70, .chat: 0.78, .writing: 0.80, .coding: 0.72, .reasoning: 0.78, .longContext: 0.75]),
        ModelDescriptor(
            id: "mlx-community/gemma-4-31b-it-4bit", name: "Gemma 4 31B", family: "Gemma", publisher: "Google DeepMind",
            summary: "Das größte Gemma-4-Modell. Sehr gute Texte, langsamer als die MoE-Variante.",
            totalParamsB: 31.0, activeParamsB: 31.0, approxBytes: 18_500_000_000, contextTokens: 262_144,
            capabilities: [.chat, .coding, .reasoning, .tools, .longContext], license: .apache2,
            quality: [.quick: 0.66, .chat: 0.82, .writing: 0.84, .coding: 0.78, .reasoning: 0.84, .longContext: 0.78]),
        ModelDescriptor(
            id: "mlx-community/Qwen3.6-27B-4bit", name: "Qwen3.6 27B", family: "Qwen", publisher: qwenAuthor,
            summary: "Dichtes Modell für Architektur, Code-Review und anspruchsvolle Analysen.",
            totalParamsB: 27.0, activeParamsB: 27.0, approxBytes: 16_500_000_000, contextTokens: 262_144,
            capabilities: [.chat, .coding, .reasoning, .tools, .longContext], license: .apache2,
            quality: [.quick: 0.66, .chat: 0.80, .writing: 0.76, .coding: 0.84, .reasoning: 0.86, .longContext: 0.80],
            supportsThinking: true),
        ModelDescriptor(
            id: "mlx-community/Qwen3.5-35B-A3B-4bit", name: "Qwen3.5 35B A3B", family: "Qwen", publisher: qwenAuthor,
            summary: "Mixture of Experts mit 3B aktiven Parametern: großes Wissen, hohes Tempo.",
            totalParamsB: 35.0, activeParamsB: 3.0, approxBytes: 20_000_000_000, contextTokens: 262_144,
            capabilities: [.chat, .coding, .reasoning, .tools, .longContext], license: .apache2,
            quality: [.quick: 0.72, .chat: 0.78, .writing: 0.74, .coding: 0.80, .reasoning: 0.80, .longContext: 0.78],
            supportsThinking: true),
        ModelDescriptor(
            id: "mlx-community/Qwen3-30B-A3B-4bit", name: "Qwen3 30B A3B", family: "Qwen", publisher: qwenAuthor,
            summary: "Bewährtes MoE-Modell mit Denkmodus.",
            totalParamsB: 30.5, activeParamsB: 3.3, approxBytes: 17_200_000_000, contextTokens: 32_768,
            capabilities: [.chat, .coding, .reasoning, .tools], license: .apache2,
            quality: [.quick: 0.70, .chat: 0.74, .writing: 0.70, .coding: 0.74, .reasoning: 0.76, .longContext: 0.45],
            supportsThinking: true),
        ModelDescriptor(
            id: "mlx-community/Qwen3-Coder-Next-4bit", name: "Qwen3-Coder-Next", family: "Qwen", publisher: qwenAuthor,
            summary: "Spezialist für Code. Braucht viel Speicher – neben Xcode und Emulator wird es knapp.",
            totalParamsB: 80.0, activeParamsB: 3.0, approxBytes: 45_000_000_000, contextTokens: 262_144,
            capabilities: [.chat, .coding, .tools, .longContext], license: .apache2,
            quality: [.quick: 0.60, .chat: 0.66, .writing: 0.60, .coding: 0.90, .reasoning: 0.78, .longContext: 0.82]),
        ModelDescriptor(
            id: "mlx-community/gpt-oss-20b-MXFP4-Q8", name: "gpt-oss 20B", family: "gpt-oss", publisher: "OpenAI",
            summary: "Offenes Modell von OpenAI mit Denkmodus. Stark beim logischen Schließen.",
            totalParamsB: 21.0, activeParamsB: 3.6, quantization: "MXFP4", approxBytes: 12_000_000_000,
            contextTokens: 131_072, capabilities: [.chat, .coding, .reasoning, .tools, .longContext], license: .apache2,
            quality: [.quick: 0.68, .chat: 0.72, .writing: 0.66, .coding: 0.74, .reasoning: 0.80, .longContext: 0.66]),
        ModelDescriptor(
            id: "mlx-community/Mistral-Nemo-Instruct-2407-4bit", name: "Mistral Nemo 12B", family: "Mistral",
            publisher: "Mistral AI & NVIDIA",
            summary: "Europäisches Modell mit gutem Deutsch und 128K Kontext.",
            totalParamsB: 12.2, activeParamsB: 12.2, approxBytes: 6_900_000_000, contextTokens: 131_072,
            capabilities: [.chat, .longContext], license: .apache2,
            quality: [.quick: 0.60, .chat: 0.66, .writing: 0.70, .coding: 0.55, .reasoning: 0.55, .longContext: 0.60]),
        ModelDescriptor(
            id: "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit", name: "DeepSeek R1 Distill 7B", family: "DeepSeek",
            publisher: "DeepSeek",
            summary: "Kleines Denkmodell. Rechnet Schritt für Schritt, antwortet dafür langsamer.",
            totalParamsB: 7.6, activeParamsB: 7.6, approxBytes: 4_300_000_000, contextTokens: 32_768,
            capabilities: [.chat, .coding, .reasoning], license: .mit,
            quality: [.quick: 0.40, .chat: 0.50, .writing: 0.45, .coding: 0.55, .reasoning: 0.68, .longContext: 0.35]),
        ModelDescriptor(
            id: "mlx-community/GLM-4-9B-0414-4bit", name: "GLM-4 9B", family: "GLM", publisher: "Z.ai",
            summary: "Allrounder unter MIT-Lizenz.",
            totalParamsB: 9.4, activeParamsB: 9.4, approxBytes: 5_300_000_000, contextTokens: 32_768,
            capabilities: [.chat, .coding, .tools], license: .mit,
            quality: [.quick: 0.60, .chat: 0.62, .writing: 0.62, .coding: 0.60, .reasoning: 0.60, .longContext: 0.35]),
        ModelDescriptor(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit", name: "Llama 3.2 3B", family: "Llama", publisher: "Meta",
            summary: "Sehr kleines Textmodell. Lizenz mit Auflagen.",
            totalParamsB: 3.2, activeParamsB: 3.2, approxBytes: 1_800_000_000, contextTokens: 131_072,
            capabilities: [.chat, .longContext], license: llama32,
            quality: [.quick: 0.55, .chat: 0.50, .writing: 0.50, .coding: 0.40, .reasoning: 0.42, .longContext: 0.40]),
        ModelDescriptor(
            id: "mlx-community/OLMo-2-1124-7B-Instruct-4bit", name: "OLMo 2 7B", family: "OLMo", publisher: "Ai2",
            summary: "Vollständig offen: Gewichte, Code und Trainingsdaten sind veröffentlicht.",
            totalParamsB: 7.3, activeParamsB: 7.3, approxBytes: 4_100_000_000, contextTokens: 4_096,
            capabilities: [.chat], license: .apache2, openness: .openSource,
            quality: [.quick: 0.50, .chat: 0.50, .writing: 0.50, .coding: 0.40, .reasoning: 0.45, .longContext: 0.20]),
    ]

    public static func descriptor(for id: String) -> ModelDescriptor? {
        models.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    /// Empfehlung für den ersten Start: klein genug für einen schnellen Download.
    public static let starterID = "mlx-community/Qwen3-4B-4bit"

    /// Modelltypen (config.json „model_type“), die LOKI 0.1 über MLX laden kann.
    public static let supportedModelTypes: Set<String> = [
        "llama", "mistral", "mistral3", "mixtral", "phi", "phi3", "phimoe", "gemma", "gemma2", "gemma3",
        "gemma3_text", "gemma3n", "gemma4", "gemma4_text", "gemma4_unified", "qwen2", "qwen3", "qwen3_moe",
        "qwen3_next", "qwen3_5", "qwen3_5_moe", "qwen3_5_text", "deepseek_v2", "deepseek_v3", "glm4",
        "glm4_moe", "glm4_moe_lite", "gpt_oss", "olmo2", "olmo3", "olmoe", "granite", "granitemoehybrid",
        "smollm3", "lfm2", "lfm2_moe", "exaone4", "ernie4_5", "cohere", "starcoder2", "internlm2", "minicpm",
        "mimo", "minimax", "falcon_h1", "nemotron_h", "apertus", "helium", "bitnet", "openelm",
    ]
}
