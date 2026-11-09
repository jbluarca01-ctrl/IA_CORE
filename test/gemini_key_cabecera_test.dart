import 'dart:convert';

import 'package:ai_core/ai_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Seguridad (Nettia SPEC-008 S2): la API key de Gemini viaja solo en la
/// cabecera x-goog-api-key, nunca en la URL (que queda en registros).
void main() {
  const key = 'TEST-KEY-cabecera-123';
  final config = AiProviderConfig(providerType: AiProviderType.gemini, apiKey: key, modelId: 'gemini-1.5-pro');
  final vistas = <Uri>[];
  final cabeceras = <String?>[];

  http.Client cliente(String cuerpo, {Map<String, String> headers = const {}}) => MockClient((r) async {
    vistas.add(r.url);
    cabeceras.add(r.headers['x-goog-api-key']);
    return http.Response(cuerpo, 200, headers: headers);
  });

  setUp(() {
    vistas.clear();
    cabeceras.clear();
  });

  test('generateContent: la key no va en la URL', () async {
    final respuesta = jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'ok'},
            ],
          },
        },
      ],
    });
    await GeminiAdapter(client: cliente(respuesta)).enviarMensaje(
      mensajes: [AiChatMessage(role: AiMessageRole.user, content: 'hola')],
      config: config,
    );
    expect(vistas.single.toString(), isNot(contains(key)));
    expect(cabeceras.single, key);
  });

  test('streamGenerateContent: la key no va en la URL', () async {
    final sse = 'data: {"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}\n\n';
    await GeminiAdapter(client: cliente(sse, headers: {'content-type': 'text/event-stream'}))
        .enviarMensajeStream(mensajes: [AiChatMessage(role: AiMessageRole.user, content: 'hola')], config: config)
        .toList();
    expect(vistas.single.toString(), isNot(contains(key)));
    expect(cabeceras.single, key);
  });

  test('listarModelos: la key no va en la URL', () async {
    await GeminiAdapter(client: cliente(jsonEncode({'models': []}))).listarModelos(apiKey: key);
    expect(vistas.single.toString(), isNot(contains(key)));
    expect(cabeceras.single, key);
  });
}
