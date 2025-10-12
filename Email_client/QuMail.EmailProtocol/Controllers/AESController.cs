using System.Net.Http;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;

namespace QuMail.EmailProtocol.Controllers
{
    [ApiController]
    [Route("api/aes")]
    public class AESController : ControllerBase
    {
        private static readonly HttpClient Http = new HttpClient();
        private readonly ILogger<AESController> _logger;

        private const string AesBaseUrl = "http://aes-server:2022";

        public AESController(ILogger<AESController> logger)
        {
            _logger = logger;
        }

        // GET api/aes/encrypt?plaintext=...
        [HttpGet("encrypt")]
        public async Task<IActionResult> Encrypt([FromQuery] string? plaintext)
        {
            if (string.IsNullOrEmpty(plaintext))
            {
                return BadRequest(new { success = false, message = "plaintext is required" });
            }

            try
            {
                var response = await Http.PostAsJsonAsync($"{AesBaseUrl}/api/gcm/encrypt", new { plaintext });
                var content = await response.Content.ReadAsStringAsync();
                if (!response.IsSuccessStatusCode)
                {
                    _logger.LogError("AES encrypt proxy failed: {Status} - {Content}", response.StatusCode, content);
                    return StatusCode((int)response.StatusCode, new { success = false, message = content });
                }

                // return raw JSON from AES server
                return Content(content, "application/json", Encoding.UTF8);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "AES encrypt proxy exception");
                return StatusCode(502, new { success = false, message = ex.Message });
            }
        }

        // GET api/aes/decrypt?envelope=<urlencoded json>
        [HttpGet("decrypt")]
        public async Task<IActionResult> Decrypt([FromQuery] string? envelope)
        {
            if (string.IsNullOrEmpty(envelope))
            {
                return BadRequest(new { success = false, message = "envelope is required" });
            }

            try
            {
                // Normalize envelope field names to snake_case expected by server2.py
                var je = JsonDocument.Parse(envelope).RootElement;
                string? keyId = je.TryGetProperty("key_id", out var kidSnake) ? kidSnake.GetString() : (je.TryGetProperty("keyId", out var kidCamel) ? kidCamel.GetString() : null);
                string? ivHex = je.TryGetProperty("iv_hex", out var ivSnake) ? ivSnake.GetString() : (je.TryGetProperty("ivHex", out var ivCamel) ? ivCamel.GetString() : null);
                string? ctHex = je.TryGetProperty("ciphertext_hex", out var ctSnake) ? ctSnake.GetString() : (je.TryGetProperty("ciphertextHex", out var ctCamel) ? ctCamel.GetString() : null);
                string? tagHex = je.TryGetProperty("tag_hex", out var tagSnake) ? tagSnake.GetString() : (je.TryGetProperty("tagHex", out var tagCamel) ? tagCamel.GetString() : null);
                string? aadHex = je.TryGetProperty("aad_hex", out var aadSnake) ? aadSnake.GetString() : (je.TryGetProperty("aadHex", out var aadCamel) ? aadCamel.GetString() : "");

                var body = new
                {
                    key_id = keyId ?? string.Empty,
                    iv_hex = ivHex ?? string.Empty,
                    ciphertext_hex = ctHex ?? string.Empty,
                    tag_hex = tagHex ?? string.Empty,
                    aad_hex = aadHex ?? string.Empty,
                };

                var response = await Http.PostAsJsonAsync($"{AesBaseUrl}/api/gcm/decrypt", body);
                var respContent = await response.Content.ReadAsStringAsync();
                if (!response.IsSuccessStatusCode)
                {
                    _logger.LogError("AES decrypt proxy failed: {Status} - {Content}", response.StatusCode, respContent);
                    return StatusCode((int)response.StatusCode, new { success = false, message = respContent });
                }

                // server2.py returns plaintext as raw text; normalize to JSON for the app
                var normalized = JsonSerializer.Serialize(new { plaintext = respContent });
                return Content(normalized, "application/json", Encoding.UTF8);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "AES decrypt proxy exception");
                return StatusCode(502, new { success = false, message = ex.Message });
            }
        }
    }
}


