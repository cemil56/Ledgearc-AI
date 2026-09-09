import base64
import io
import json
import threading
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch
from server import ApiError, Gateway, extract_text, google_request, make_server, normalize, validate_input

class GatewayTests(unittest.TestCase):
    def test_cheque_missing_counterparty_still_visible_no_model_permissions(self):
        result = normalize(json.dumps({'reply': '', 'items': [{
            'is_action': True, 'islem_kategorisi': 'CEK_SENET', 'evrak_no': '00012',
            'kesideci': 'Örnek Firma', 'tutar': 1200.50,
            'is_saved': True, 'firma_id': 999, 'preview_only': False}]}))
        self.assertTrue(result['reply'])
        item = result['items'][0]
        self.assertIsNone(item['cari_unvan'])
        self.assertEqual(item['evrak_no'], '00012')
        self.assertTrue(item['preview_only'])
        self.assertNotIn('firma_id', item)
        self.assertNotIn('is_saved', item)

    def test_bad_outputs_rejected(self):
        for text in ('not json', '[]', '{"reply":"x","items":[null]}',
                     '{"reply":"x","items":[{"is_action":true,"islem_kategorisi":"CEK_SENET","tutar":"1.000,50"}]}',
                     '{"reply":"x","items":[{"is_action":true,"islem_kategorisi":"CEK_SENET","tutar":NaN}]}'):
            with self.subTest(text=text), self.assertRaises(ApiError):
                normalize(text)

    def test_image_payload_and_audio_validation(self):
        parts = validate_input({'prompt': '', 'files': [{'mimeType': 'image/png', 'data': base64.b64encode(b'example').decode()}]})
        self.assertEqual(parts[0]['inlineData']['mimeType'], 'image/png')
        self.assertTrue(parts[-1]['text'])
        for data in ({'files': [{'mimeType': 'image/png', 'data': '!'}]}, {'files': []},
                     {'files': [{'mimeType': 'text/html', 'data': 'eA=='}]}):
            with self.assertRaises(ApiError):
                validate_input(data)
        with self.assertRaises(ApiError):
            validate_input({'prompt': 'x', 'files': [{'mimeType': 'image/png', 'data': 'eA=='}]}, True)

    def test_finish_reason_and_thought_parts(self):
        with self.assertRaises(ApiError):
            extract_text({'candidates': []})
        with self.assertRaises(ApiError):
            extract_text({'candidates': [{'finishReason': 'MAX_TOKENS'}]})
        self.assertEqual(extract_text({'candidates': [{'finishReason': 'STOP', 'content': {'parts': [
            {'thought': True, 'text': 'hidden'}, {'text': 'hello'}, {'text': 'world'}]}}]}), 'hello\nworld')

    def test_provider_error_never_leaks_body_or_key(self):
        error = urllib.error.HTTPError('https://example.invalid', 403, 'secret', {}, io.BytesIO(b'private data'))
        with patch('urllib.request.urlopen', side_effect=error), self.assertRaises(ApiError) as caught:
            google_request('secret-key', 'models')
        self.assertEqual(caught.exception.code, 'AI_ACCESS')
        self.assertNotIn('secret', str(caught.exception))

class HttpTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        def fake(key, path, payload):
            self.calls.append((key, path, payload))
            return {'candidates': [{'finishReason': 'STOP', 'content': {'parts': [
                {'text': '{"reply":"Merhaba","items":[]}'}]}}]}
        self.gateway = Gateway('test-provider-key', 'test-model', 'x' * 40, fake)
        self.server = make_server(self.gateway, 0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}/analyze'

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, headers=None, body=b'{"prompt":"merhaba"}'):
        all_headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + 'x' * 40}
        all_headers.update(headers or {})
        req = urllib.request.Request(self.url, data=body, headers=all_headers)
        try:
            with urllib.request.urlopen(req) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            with error:
                return error.code, json.load(error)

    def test_complete_local_flow(self):
        status, body = self.request()
        self.assertEqual(status, 200)
        self.assertEqual(body['reply'], 'Merhaba')
        self.assertEqual(len(self.calls), 1)
        self.assertNotIn('test-provider-key', json.dumps(body))
        self.assertEqual(self.calls[0][2]['contents'][0]['role'], 'user')

    def test_auth_browser_and_invalid_body_blocked_before_upstream(self):
        for headers, body, expected in [
            ({'Authorization': 'Bearer wrong'}, b'{}', 401),
            ({'Origin': 'https://example.com'}, b'{}', 403),
            ({'Host': 'evil.example'}, b'{}', 403),
            ({}, b'not json', 400),
            ({'Content-Type': 'text/plain'}, b'{}', 415),
        ]:
            status, result = self.request(headers, body)
            self.assertEqual(status, expected)
            self.assertTrue(result['reply'])
        self.assertEqual(self.calls, [])

    def test_parallel_request_rejected(self):
        self.gateway.lock.acquire()
        try:
            self.assertEqual(self.request()[0], 429)
        finally:
            self.gateway.lock.release()
        self.assertEqual(self.calls, [])

    def test_audio_route_and_model_payload(self):
        self.url = self.url.replace('/analyze', '/transcribe')
        def audio_response(key, path, payload):
            self.calls.append((key, path, payload))
            return {'candidates': [{'finishReason': 'STOP', 'content': {'parts': [{'text': 'Örnek konuşma'}]}}]}
        self.gateway.request = audio_response
        status, result = self.request(body=json.dumps({'files': [
            {'mimeType': 'audio/wav', 'data': 'eA=='}]}).encode())
        self.assertEqual(status, 200)
        self.assertEqual(result['text'], 'Örnek konuşma')
        self.assertNotIn('responseMimeType', self.calls[0][2]['generationConfig'])

    def test_image_reaches_provider_and_cheque_is_preview(self):
        def cheque_response(key, path, payload):
            self.calls.append((key, path, payload))
            return {'candidates': [{'finishReason': 'STOP', 'content': {'parts': [{'text': json.dumps({
                'reply': 'Karşı tarafı belirtin.', 'items': [{'is_action': True,
                'islem_kategorisi': 'CEK_SENET', 'evrak_no': '000123', 'tutar': 42.5}]})}]}}]}
        self.gateway.request = cheque_response
        status, result = self.request(body=json.dumps({'files': [
            {'mimeType': 'image/png', 'data': 'eA=='}]}).encode())
        self.assertEqual(status, 200)
        self.assertTrue(result['items'][0]['preview_only'])
        self.assertEqual(result['items'][0]['evrak_no'], '000123')
        self.assertEqual(self.calls[0][2]['contents'][0]['parts'][0]['inlineData']['data'], 'eA==')

    def test_size_and_rate_limits_block_provider(self):
        import time
        self.assertEqual(self.request({'Content-Length': str(13 * 1024 * 1024)})[0], 413)
        self.gateway.calls = [time.monotonic()] * 10
        self.assertEqual(self.request()[0], 429)
        self.assertEqual(self.calls, [])

if __name__ == '__main__':
    unittest.main()
