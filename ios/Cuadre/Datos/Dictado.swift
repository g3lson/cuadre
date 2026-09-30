import Foundation
import Speech
import AVFoundation

/// DICTAR.
///
/// Reconocimiento de voz de iOS, y **en el propio teléfono** cuando el idioma lo
/// permite (`requiresOnDeviceRecognition`): el audio de alguien diciendo lo que
/// va a comprar no tiene por qué salir del aparato, y además así funciona en el
/// parqueo del súper sin señal.
///
/// Se transcribe según se habla y el texto se va escribiendo en el cuadro, que
/// es lo que hace que se note que está funcionando. Si no, la gente repite.
@Observable
@MainActor
final class Dictado {
    private(set) var escuchando = false
    private(set) var error: String?
    /// Lo que se lleva dicho en esta tanda.
    private(set) var texto = ""

    private let motor = AVAudioEngine()
    private var peticion: SFSpeechAudioBufferRecognitionRequest?
    private var tarea: SFSpeechRecognitionTask?
    private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-DO"))
        ?? SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))

    var sePuede: Bool { reconocedor?.isAvailable == true }

    /// Enciende o apaga. Un solo botón, porque un botón para empezar y otro para
    /// parar es un botón de más en una pantalla que se usa con una mano.
    func alterna(_ alTexto: @escaping (String) -> Void) {
        if escuchando { para() } else { empieza(alTexto) }
    }

    private func empieza(_ alTexto: @escaping (String) -> Void) {
        error = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] permiso in
            Task { @MainActor in
                guard let self else { return }
                guard permiso == .authorized else {
                    self.error = "Para dictar hace falta darle permiso a Cuadre en Ajustes del iPhone."
                    return
                }
                AVAudioApplication.requestRecordPermission { micro in
                    Task { @MainActor in
                        guard micro else {
                            self.error = "Para dictar hace falta el micrófono."
                            return
                        }
                        self.arranca(alTexto)
                    }
                }
            }
        }
    }

    private func arranca(_ alTexto: @escaping (String) -> Void) {
        guard let reconocedor, reconocedor.isAvailable else {
            error = "El dictado no está disponible ahora mismo."
            return
        }
        do {
            let sesion = AVAudioSession.sharedInstance()
            // `.record` y no `.playAndRecord`: no hay nada que sonar, y pedir
            // salida de audio para grabar corta la música de quien la lleve puesta.
            try sesion.setCategory(.record, mode: .measurement, options: .duckOthers)
            try sesion.setActive(true, options: .notifyOthersOnDeactivation)

            let p = SFSpeechAudioBufferRecognitionRequest()
            p.shouldReportPartialResults = true
            if reconocedor.supportsOnDeviceRecognition { p.requiresOnDeviceRecognition = true }
            peticion = p

            let entrada = motor.inputNode
            let formato = entrada.outputFormat(forBus: 0)
            entrada.removeTap(onBus: 0)
            entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { buffer, _ in
                p.append(buffer)
            }
            motor.prepare()
            try motor.start()
            escuchando = true
            texto = ""

            tarea = reconocedor.recognitionTask(with: p) { [weak self] resultado, fallo in
                Task { @MainActor in
                    guard let self else { return }
                    if let resultado {
                        self.texto = resultado.bestTranscription.formattedString
                        alTexto(self.texto)
                    }
                    if fallo != nil || resultado?.isFinal == true { self.para() }
                }
            }
        } catch {
            self.error = "No pude encender el micrófono."
            para()
        }
    }

    func para() {
        motor.inputNode.removeTap(onBus: 0)
        if motor.isRunning { motor.stop() }
        peticion?.endAudio()
        tarea?.cancel()
        peticion = nil
        tarea = nil
        escuchando = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
