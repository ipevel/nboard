<?php

namespace Tests\Unit\Services;

use App\Services\ImageCaptchaService;
use Illuminate\Support\Facades\Cache;
use RuntimeException;
use Tests\TestCase;

class ImageCaptchaTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config(['cache.default' => 'array']);
        Cache::purge();
    }

    public function test_available_returns_false_when_gd_functions_are_missing(): void
    {
        $service = new class extends ImageCaptchaService {
            protected static function functionExists(string $function): bool
            {
                return false;
            }
        };

        $this->assertFalse($service::available());
    }

    public function test_create_returns_hex_id_and_png_data_uri(): void
    {
        if (!ImageCaptchaService::available()) {
            $this->markTestSkipped('GD extension is not available');
        }

        $result = (new ImageCaptchaService())->create('register', null, '203.0.113.10');

        $this->assertMatchesRegularExpression('/^[a-f0-9]{64}$/', $result['id']);
        $this->assertStringStartsWith('data:image/png;base64,', $result['image']);
        $this->assertGreaterThan(0, strlen(base64_decode(substr($result['image'], strlen('data:image/png;base64,')))));
    }

    public function test_verify_accepts_correct_code_only_once(): void
    {
        $service = $this->serviceWithFixedCode('ABC123');
        $captcha = $service->create('register', null, '203.0.113.11');

        $this->assertTrue($service->verify($captcha['id'], 'ABC123', 'register'));
        $this->assertFalse($service->verify($captcha['id'], 'ABC123', 'register'));
    }

    public function test_verify_rejects_wrong_code(): void
    {
        $service = $this->serviceWithFixedCode('ABC123');
        $captcha = $service->create('register', null, '203.0.113.12');

        $this->assertFalse($service->verify($captcha['id'], 'ABC124', 'register'));
        $this->assertTrue($service->verify($captcha['id'], 'ABC123', 'register'));
    }

    public function test_verify_rejects_expired_record(): void
    {
        $service = $this->serviceWithFixedCode('ABC123');
        $captcha = $service->create('register', null, '203.0.113.13');

        Cache::put(ImageCaptchaService::CACHE_PREFIX . $captcha['id'], [
            'digest' => hash_hmac('sha256', 'ABC123', $captcha['id']),
            'purpose' => 'register',
            'expires_at' => time() - 1,
        ], ImageCaptchaService::TTL);

        $this->assertFalse($service->verify($captcha['id'], 'ABC123', 'register'));
    }

    public function test_verify_rejects_purpose_mismatch(): void
    {
        $service = $this->serviceWithFixedCode('ABC123');
        $captcha = $service->create('register', null, '203.0.113.14');

        $this->assertFalse($service->verify($captcha['id'], 'ABC123', 'email'));
        $this->assertTrue($service->verify($captcha['id'], 'ABC123', 'register'));
    }

    public function test_verify_rejects_malformed_id(): void
    {
        $service = $this->serviceWithFixedCode('ABC123');

        $this->assertFalse($service->verify(null, 'ABC123', 'register'));
        $this->assertFalse($service->verify('not-a-valid-id', 'ABC123', 'register'));
        $this->assertFalse($service->verify(str_repeat('Z', 64), 'ABC123', 'register'));
    }

    public function test_create_rejects_unknown_purpose(): void
    {
        $this->expectException(\InvalidArgumentException::class);

        (new ImageCaptchaService())->create('login', null, '203.0.113.15');
    }

    public function test_create_is_rate_limited_per_ip(): void
    {
        $service = $this->serviceWithFixedCode('ABC123');
        $ip = '203.0.113.16';

        for ($index = 0; $index < ImageCaptchaService::RATE_LIMIT; $index++) {
            $service->create('register', null, $ip);
        }

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('rate limited');

        $service->create('register', null, $ip);
    }

    public function test_create_invalidates_previous_captcha(): void
    {
        $service = $this->serviceWithFixedCode('ABC123');
        $first = $service->create('register', null, '203.0.113.17');
        $second = $service->create('register', $first['id'], '203.0.113.17');

        $this->assertFalse($service->verify($first['id'], 'ABC123', 'register'));
        $this->assertTrue($service->verify($second['id'], 'ABC123', 'register'));
    }

    private function serviceWithFixedCode(string $code): ImageCaptchaService
    {
        return new class($code) extends ImageCaptchaService {
            public function __construct(private readonly string $fixedCode)
            {
            }

            protected function generateCode(): string
            {
                return $this->fixedCode;
            }
        };
    }
}
