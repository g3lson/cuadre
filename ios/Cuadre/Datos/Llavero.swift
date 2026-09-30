import Foundation
import Security

/// EL LLAVERO.
///
/// El testigo de sesión va aquí y no en `UserDefaults`. `UserDefaults` es un
/// archivo dentro de la copia de seguridad: un respaldo del iPhone en el
/// ordenador de otro incluiría la sesión. El llavero con
/// `WhenUnlockedThisDeviceOnly` no sale del aparato ni entra en la copia.
enum Llavero {
    private static let servicio = "do.com.fente.cuadre"

    static func guarda(_ valor: String, para clave: String) {
        borra(clave)
        guard let datos = valor.data(using: .utf8) else { return }
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicio,
            kSecAttrAccount as String: clave,
            kSecValueData as String: datos,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(consulta as CFDictionary, nil)
    }

    static func lee(_ clave: String) -> String? {
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicio,
            kSecAttrAccount as String: clave,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var salida: CFTypeRef?
        guard SecItemCopyMatching(consulta as CFDictionary, &salida) == errSecSuccess,
              let datos = salida as? Data else { return nil }
        return String(data: datos, encoding: .utf8)
    }

    static func borra(_ clave: String) {
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicio,
            kSecAttrAccount as String: clave,
        ]
        SecItemDelete(consulta as CFDictionary)
    }
}
