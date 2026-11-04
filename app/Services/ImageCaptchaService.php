<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\RateLimiter;
use InvalidArgumentException;
use RuntimeException;

class ImageCaptchaService
{
    public const TTL = 120;

    public const PURPOSES = ['register', 'email'];

    public const CACHE_PREFIX = 'IMAGE_CAPTCHA:';

    public const CODE_LENGTH = 6;

    public const CODE_CHARSET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

    public const RATE_LIMIT = 20;

    public const RATE_WINDOW = 60;

    private const WIDTH = 180;

    private const HEIGHT = 56;

    private const REQUIRED_FUNCTIONS = [
        'imagecreatetruecolor',
        'imagecolorallocate',
        'imagefill',
        'imageline',
        'imagesetpixel',
        'imagestring',
        'imagecopyresampled',
        'imagepng',
        'imagesx',
        'imagesy',
        'imagedestroy',
    ];

    /**
     * 当前运行环境是否具备生成图片验证码所需的能力
     */
    public static function available(): bool
    {
        foreach (self::REQUIRED_FUNCTIONS as $function) {
            if (!static::functionExists($function)) {
                return false;
            }
        }

        return true;
    }

    /**
     * 生成一张新的图片验证码
     *
     * @return array{id: string, image: string}
     */
    public function create(string $purpose, ?string $previousId, string $ip): array
    {
        if (!in_array($purpose, self::PURPOSES, true)) {
            throw new InvalidArgumentException('invalid captcha purpose');
        }

        if (!static::available()) {
            throw new RuntimeException('gd extension is required');
        }

        $this->assertRateLimit($ip);

        if ($previousId !== null && $previousId !== '') {
            if ($this->isValidId($previousId)) {
                Cache::forget(self::CACHE_PREFIX . $previousId);
            }
        }

        $code = $this->generateCode();
        $id = bin2hex(random_bytes(32));

        Cache::put(self::CACHE_PREFIX . $id, [
            'digest' => hash_hmac('sha256', $code, $id),
            'purpose' => $purpose,
            'expires_at' => time() + self::TTL,
        ], self::TTL);

        return [
            'id' => $id,
            'image' => 'data:image/png;base64,' . base64_encode($this->render($code)),
        ];
    }

    /**
     * 校验图片验证码，成功后立即失效
     */
    public function verify(?string $id, ?string $code, string $purpose): bool
    {
        if (!in_array($purpose, self::PURPOSES, true)) {
            return false;
        }

        if ($id === null || !$this->isValidId($id)) {
            return false;
        }

        if ($code === null) {
            return false;
        }

        $code = strtoupper(trim($code));
        if (strlen($code) !== self::CODE_LENGTH) {
            return false;
        }
        if (strspn($code, self::CODE_CHARSET) !== strlen($code)) {
            return false;
        }

        $key = self::CACHE_PREFIX . $id;
        $record = Cache::get($key);
        if (!is_array($record)) {
            return false;
        }

        if (($record['purpose'] ?? null) !== $purpose) {
            return false;
        }

        if ((int) ($record['expires_at'] ?? 0) < time()) {
            Cache::forget($key);
            return false;
        }

        $digest = hash_hmac('sha256', $code, $id);
        if (!hash_equals((string) ($record['digest'] ?? ''), $digest)) {
            return false;
        }

        Cache::forget($key);

        return true;
    }

    protected function generateCode(): string
    {
        $charset = self::CODE_CHARSET;
        $max = strlen($charset) - 1;
        $code = '';

        for ($index = 0; $index < self::CODE_LENGTH; $index++) {
            $code .= $charset[random_int(0, $max)];
        }

        return $code;
    }

    protected static function functionExists(string $function): bool
    {
        return function_exists($function);
    }

    private function isValidId(string $id): bool
    {
        return preg_match('/^[a-f0-9]{64}$/', $id) === 1;
    }

    /**
     * 按 IP 限制生成频率，使用缓存锁避免并发绕过
     */
    private function assertRateLimit(string $ip): void
    {
        $hash = hash('sha256', $ip);
        $limiterKey = 'IMAGE_CAPTCHA_RATE:' . $hash;
        $lock = Cache::lock($limiterKey . ':lock', 10);

        if (!$lock->get()) {
            throw new RuntimeException('rate limited');
        }

        try {
            if (RateLimiter::tooManyAttempts($limiterKey, self::RATE_LIMIT)) {
                throw new RuntimeException('rate limited');
            }

            RateLimiter::hit($limiterKey, self::RATE_WINDOW);
        } finally {
            $lock->release();
        }
    }

    /**
     * 渲染 PNG 二进制内容
     */
    private function render(string $code): string
    {
        $width = self::WIDTH;
        $height = self::HEIGHT;

        $image = imagecreatetruecolor($width, $height);
        $background = imagecolorallocate($image, 247, 249, 252);
        imagefill($image, 0, 0, $background);

        for ($line = 0; $line < 5; $line++) {
            $color = imagecolorallocate(
                $image,
                random_int(168, 208),
                random_int(178, 214),
                random_int(196, 228)
            );
            imageline(
                $image,
                random_int(0, $width),
                random_int(0, $height),
                random_int(0, $width),
                random_int(0, $height),
                $color
            );
        }

        $characters = str_split($code);
        $slotWidth = intdiv($width - 20, count($characters));
        $fontWidth = imagefontwidth(5);
        $fontHeight = imagefontheight(5);

        foreach ($characters as $index => $character) {
            $glyph = imagecreatetruecolor($slotWidth, $height);
            $transparent = imagecolorallocatealpha($glyph, 0, 0, 0, 127);
            imagefill($glyph, 0, 0, $transparent);

            $textColor = imagecolorallocate(
                $glyph,
                random_int(28, 78),
                random_int(38, 88),
                random_int(58, 118)
            );

            $glyphX = max(0, intdiv($slotWidth - $fontWidth, 2));
            $glyphY = max(0, intdiv($height - $fontHeight, 2)) + random_int(-4, 4);
            imagestring($glyph, 5, $glyphX, $glyphY, $character, $textColor);

            $glyph = $this->rotateGlyph($glyph, $transparent);
            $glyphWidth = imagesx($glyph);
            $glyphHeight = imagesy($glyph);

            $scale = random_int(95, 115) / 100;
            $targetWidth = max(1, (int) round($glyphWidth * $scale));
            $targetHeight = max(1, (int) round($glyphHeight * $scale));
            $targetX = 10 + $index * $slotWidth + intdiv($slotWidth - $targetWidth, 2);
            $targetY = intdiv($height - $targetHeight, 2) + random_int(-3, 3);

            imagecopyresampled(
                $image,
                $glyph,
                $targetX,
                $targetY,
                0,
                0,
                $targetWidth,
                $targetHeight,
                $glyphWidth,
                $glyphHeight
            );

            imagedestroy($glyph);
        }

        for ($pixel = 0; $pixel < 120; $pixel++) {
            $color = imagecolorallocate(
                $image,
                random_int(150, 220),
                random_int(160, 225),
                random_int(180, 235)
            );
            imagesetpixel($image, random_int(0, $width - 1), random_int(0, $height - 1), $color);
        }

        ob_start();
        imagepng($image);
        $png = (string) ob_get_clean();
        imagedestroy($image);

        return $png;
    }

    /**
     * 对单个字符做轻微旋转，旋转能力缺失时返回原图
     *
     * @param \GdImage $glyph
     * @param int $transparent
     * @return \GdImage
     */
    private function rotateGlyph($glyph, int $transparent)
    {
        $angle = random_int(-12, 12);

        if ($angle === 0 || !function_exists('imagerotate')) {
            return $glyph;
        }

        $rotated = imagerotate($glyph, $angle, $transparent);
        if ($rotated === false) {
            return $glyph;
        }

        imagedestroy($glyph);

        return $rotated;
    }
}
