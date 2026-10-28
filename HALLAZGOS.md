# Hallazgos — Issues de KonnectMac

> **Nota:** este documento se escribió antes del renombre del fork a **Apfelbindung**.
> Las rutas `KonnectMac/...` que aparecen abajo corresponden a la estructura anterior;
> hoy los archivos viven en `Apfelbindung/...`. El upstream sigue siendo
> `aryarajsingh/KonnectMac`.

Fecha de revisión: 2026-09-22
Repo clonado: `rockmadehome/KonnectMac` (fork)
Upstream: `aryarajsingh/KonnectMac`
Branch: `stable`
HEAD: `493b07818d32c38036fde491cae46f6c7f8ea33e` (2026-04-20)

Los issues del upstream se pudieron leer vía la API pública de GitHub (sin auth).
Al momento de la revisión hay **6 issues abiertos** (ninguno cerrado).

## Resumen

| # | Título | Tipo | Estado frente al fork (`493b078`) |
|---|--------|------|-----------------------------------|
| 7 | [Feature Request] Homebrew Cask | Feature | No implementado |
| 6 | [Feature request] Intel support | Feature | No confirmado (sin overrides de arch) |
| 5 | Duplicate-connection check rechaza conexiones de otro device | Bug | **Parece resuelto** en el fork |
| 4 | Broadcasts UDP cada 15s resetean el TLS handshake en Android | Bug | **Aún presente** |
| 3 | Pair handshake se cuelga tras TLS (ambos lados timeout) | Bug | Sin diagnosticar (requiere device) |
| 2 | Volume control support | Feature | No implementado |

---

## #7 — Homebrew Cask (feature)

Pedido simple: publicar la app como cask de Homebrew. No hay `Casks/*.rb` ni
tap en el repo. No hay relación con bugs de protocolo.

## #6 — Intel support (feature)

Se pide que corra en Macs Intel. En `KonnectMac.xcodeproj/project.pbxproj` **no hay
`ARCHS` / `EXCLUDED_ARCHS` explícitos**; el soporte dependerá del target de despliegue
y de los binarios/dependencias. Sin un Xcode/CI aquí no se puede confirmar el motivo
exacto del fallo en Intel. Requiere verificación en macOS.

## #5 — Duplicate-connection check (bug) — PARECE RESUELTO

El issue describe (sobre el commit `30042be`) código así:

```swift
let sameHost = conn.host == host
let sameDevice = conn.remoteDeviceId != nil && tlsEstablishedDeviceIds.contains(conn.remoteDeviceId!)
guard sameHost || sameDevice else { continue }
```

El problema: `sameDevice` era verdadero para *cualquier* conexión existente con TLS
completo, sin comparar contra el device entrante (que todavía no se conoce en ese punto).

En el fork actual el chequeo quedó limitado a `sameHost`:

- `KonnectMac/Core/DeviceManager.swift:334-335`
  ```swift
  let sameHost = conn.host == host
  guard sameHost else { continue }
  ```

Es, de hecho, una de las dos correcciones que el issue sugería ("limitarse a `sameHost`
en esta etapa, o diferir hasta leer el identity packet"). **La lógica problemática
descrita ya no está presente.** La decisión por `deviceId` sigue pasando después, en
`handleIncomingSocket` / registro de conexión (`DeviceManager.swift:664-675`).

Nota: el issue se reportó con un solo device, así que no hubo reproducción real.
Conviene validar con dos dispositivos antes de cerrarlo.

## #4 — Broadcast UDP cada 15s (bug) — AÚN PRESENTE

El timer de broadcast sigue siendo incondicional:

- `KonnectMac/Core/DeviceManager.swift:163-172` — `startBroadcastTimer()`
  ```
  Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { ... broadcastIdentity() ... }
  ```
- `KonnectMac/Core/DeviceManager.swift:182-199` — `broadcastIdentity()`
  siempre hace `udpDiscovery.broadcast(packet: identity)`.
  (Solo la parte de conexión directa Tailscale está condicionada a que el phone
  no esté ya conectado; el broadcast UDP no.)

Del lado receptor, una conexión entrante con TLS establecido y socket vivo se
rechaza cerrando el fd antes de leer el identity / arrancar TLS:

- `KonnectMac/Core/DeviceManager.swift:350-379` — `handleIncomingSocket()`
  ```swift
  if conn.running {
      if isSocketAlive(conn.fd) {
          ...
          KLog.log("[TCP] Rejecting incoming from \(host) — existing TLS connection fd=\(conn.fd) ...")
          Darwin.close(fd)
          return
      }
  }
  ```

Resultado: Android responde al broadcast abriendo TCP + TLS y recibe `Connection reset`
cada 15s (ruido de log; sin impacto funcional observado). La propia implementación
oficial de KDE Connect solo emite broadcasts en `onStart()` y en cambios de red
debounced, no en un timer periódico fijo. Alineado con el fix sugerido: **suspender el
broadcast mientras hay una sesión autenticada, o no anunciarse a peers ya conectados.**

## #3 — Pair handshake se cuelga tras TLS (bug, bloqueante)

Síntoma: UDP bidireccional OK; TCP llega a ESTABLISHED; TLS arranca; ambos lados
quedan idle y la Mac cierra a los ~16s. El phone nunca muestra el prompt de pairing.
100% reproducible; LocalSend funciona en el mismo entorno → no es red.

Hipótesis del reporte: mismatch de formato/firma del *pair packet* contra KDE Connect
Android v7.

En el repo, el pair packet es mínimo:

- `KonnectMac/Core/NetworkPacket.swift:68-71`
  ```swift
  static func pairPacket(pair: Bool) -> NetworkPacket {
      return NetworkPacket(type: "kdeconnect.pair", body: ["pair": AnyCodable(pair)])
  }
  ```

No se puede confirmar/descartar el mismatch sin un dispositivo Android con KDE Connect
(no disponibles en este VPS). El issue pide verificar el flujo de firma/validación del
payload contra la versión actual de Android. **Pendiente de reproducir con device.**

## #2 — Volume control (feature)

Se pide control de volumen del output de macOS (equivalente al plugin
`systemvolumeplugin-macos.cpp` de KDE Connect Qt). No existe plugin de volumen en
`KonnectMac/Plugins/` (Battery, Clipboard, FindMyPhone, Notification, Ping, SMS,
Share, Telephony). No implementado.

---

## Notas de entorno

- No es posible compilar ni ejecutar la app aquí: es un VPS Linux sin Xcode/macOS.
- Los análisis de #4 y #5 se basan en lectura del código del fork actual.
- #3 requiere hardware (Mac + Android) y no se pudo reproducir.
- `gh` CLI tiene un token inválido (`rockmadehome`); los issues se leyeron por API pública.

---

# Revisión de reconnect y estándar KDE Connect (2026-09-22)

Comparación contra `kdeconnect-kde` (desktop, master) y `kdeconnect-android` (master),
y contra el upstream `aryarajsingh/KonnectMac` (`stable`, ya bastante más adelante que
este fork). El fork está parado sobre `v1.2` + 13 commits propios y **reintrodujo bugs
que upstream ya había corregido** (ver `Network/KDEConnection.swift` de upstream).

## Ya aplicado en esta sesión (fixes 1–4)

1. **Close-notify TLS roto en `disconnect()`** — `KDEConnection.swift`.
   El fork hacía `sslFdPtr?.pointee = -1` antes de `SSLClose()`, así que el `close_notify`
   nunca se enviaba y el peer solo notaba la caída por RST/keepalive (lento), incluso
   mandando `pair=false` (unpair-by-remote) tras un relanzamiento. Se eliminó esa línea
   (alineado con upstream). El loop sale por el `SO_RCVTIMEO` de 500 ms.
2. **Broadcast UDP periódico mientras hay sesión pareada** — `DeviceManager.swift`.
   El timer de 15 s ahora no emite si `hasActivePairedConnection`; al caer la sesión
   `handleDisconnection` vuelve a anunciarse. Estándar: anunciar solo en start y en
   cambios de red. Esto elimina el churn de #4 (Android resetea su link en cada identidad
   recibida, no chequea link existente).
3. **Backoff envenenado** — `DeviceManager.swift`. `consecutiveTLSFailures` ahora se
   limpia en `forceDisconnectAll()` y al recuperarse la red; antes sobrevivía al wake y
   `reconnectPairedDevices` quedaba throttleado hasta 300 s.
4. **Puerto UDP** — `Config.udpPort = 1716` fijo; `minPort` 1714 → 1716; se escucha en
   1716 y se emite un solo datagrama a 1716 (antes 51 por dirección). Si el puerto TCP
   caía fuera de 1716, el Mac no recibía broadcasts del teléfono.

## Pendiente para próxima sesión (5–6)

> **ACTUALIZACIÓN 2026-10-13:** los ítems 5 y 6 fueron implementados en v3.0
> (salvo el *connection packet* pre-TLS de v8, omitido a propósito — Android lo
> trata como opcional y enviar una línea JSON extra pre-TLS arriesga romper el
> parser de identidad de Android). Ver commits de v3.0.

### 5. Reconnect robusto (bajo riesgo, no toca protocolo) — ✅ IMPLEMENTADO v3.0

- `DeviceManager.swift:~230` (`reconnectPairedDevices`): usar `device.tcpPort` (puerto
  real aprendido por discovery) con fallback a `Config.defaultPort`, en vez de
  `Config.defaultPort` fijo. Un teléfono con TCP != 1716 nunca es dialeable. ✅
- `KDEConnection.connectAndRun()` (`~99-100`): `SO_SNDTIMEO` **no acota `connect()` en
  macOS**. Un IP guardado inalcanzable cuelga ~75 s la queue. Implementar connect
  no bloqueante (`O_NONBLOCK`) + `select`/`poll` con deadline de 10 s, o mover el dial a
  un hilo con timeout. Upstream ya lo intenta con `SocketHelpers`, revisar su enfoque. ✅ (O_NONBLOCK + poll 10s)
- Revisar keepalive: el fork lo bajó a 10 s/5 s/3 (~25 s); upstream usa 60 s/15 s/4
  comentando explícitamente que el idle de 60 s es para no despertar al teléfono en Doze.
  Volver al perfil de upstream salvo evidencia contraria. ✅ (60/15/4)
- `checkConnectionHealth()` está vacío pero se crea un timer de 5 s: o se implementa un
  health check real (que no dependa del `isSocketAlive` basado en `SO_ERROR`, que no
  detecta half-open) o se elimina el timer. ✅ (timer eliminado; solo keepalive TCP)
- `handleIncomingSocket` (`~350-379`) rechaza entrantes si cree que hay TLS sano con
  `idle ≤ 10`. KDE Connect siempre reemplaza el link ante una conexión nueva (validando
  cert). Evaluar aceptar siempre y dejar que el dedupe por `deviceId` decida. ✅ (siempre reemplaza)

### 6. Subir a protocolVersion 8 (requiere device Android + Mac; sesión aparte) — ✅ IMPLEMENTADO v3.0

Hoy `NetworkPacket.swift:61` anuncia `protocolVersion: 7`. Android todavía acepta v7
(por eso "generalmente anda"), pero el desktop actual **rechaza `< 8`**
(`lanlinkprovider.cpp:300,548`). Cambios necesarios:

- `identityPacket()`: `protocolVersion: 8`. ✅
- `pairPacket(pair:)`: agregar `timestamp` (segundos unix). Android exige `timestamp`
  (±30 min) para v8; sin él **descarta el pair request** (`PairingHandler.kt:71-85`). ✅
- `VerificationKeyHelper`: la clave v8 es `SHA256(sortedConcat(SPKI_A, SPKI_B) + timestamp)`
  (`PairingHandler.kt:263-266`, `pairinghandler.cpp:188-208`); la actual no incluye el
  timestamp. Cachear el timestamp con el que se envió/recibió el request para mostrarla. ✅
  (`DeviceManager.pairTimestamps`; el que responde hace echo del timestamp del request)
- Paquete pre-TLS de salida: v8 usa un *connection packet* con `targetDeviceId` y
  `targetProtocolVersion` (`deviceinfo.h:128-137`). Android lo tolera opcional, el
  desktop v8 lo valida (`isValidConnectionPacket`). ⏭️ OMITIDO (ver nota arriba)
- Identidad TLS **fresca por conexión** (upstream `882a92e` / `CertificateManager.freshTransferIdentity`).
  La `SecIdentity` cacheada queda rota tras sleep/wake y los handshakes fallan con -9810
  hasta reiniciar la app; esto es lo que rompía re-pair tras dormir. ✅ (TransferIdentity portada del upstream)
- Revisar capabilities de `kdeconnect.pair` una vez en v8. ✅ (sin cambios requeridos; capabilities siguen en identity)

> **No verificable en este entorno** (VPS Linux sin Xcode/macOS). Todo cambio de 5–6
> debe compilar y probarse contra un Android real antes de push a `stable`.
