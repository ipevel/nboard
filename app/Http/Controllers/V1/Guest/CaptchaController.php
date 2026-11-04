<?php

namespace App\Http\Controllers\V1\Guest;

use App\Http\Controllers\Controller;
use App\Services\ImageCaptchaService;
use Illuminate\Http\Request;
use InvalidArgumentException;
use RuntimeException;

class CaptchaController extends Controller
{
    public function create(Request $request)
    {
        if (admin_setting('captcha_type', 'recaptcha') !== 'image') {
            return $this->fail([404, __('Not Found')]);
        }

        if (!ImageCaptchaService::available()) {
            return $this->fail([503, __('Image captcha requires the GD extension')]);
        }

        $purpose = $request->input('purpose', 'register');
        if (!is_string($purpose) || !in_array($purpose, ImageCaptchaService::PURPOSES, true)) {
            return $this->fail([422, __('Invalid captcha purpose')]);
        }

        $previousId = $request->input('previous_id');
        if ($previousId !== null && $previousId !== '' && !preg_match('/^[a-f0-9]{64}$/', (string) $previousId)) {
            return $this->fail([422, __('Invalid captcha id')]);
        }

        try {
            $data = app(ImageCaptchaService::class)->create(
                $purpose,
                is_string($previousId) && $previousId !== '' ? $previousId : null,
                (string) $request->ip()
            );
        } catch (InvalidArgumentException $exception) {
            return $this->fail([422, __('Invalid captcha purpose')]);
        } catch (RuntimeException $exception) {
            if ($exception->getMessage() === 'rate limited') {
                return $this->fail([429, __('Too many requests')]);
            }

            return $this->fail([503, __('Image captcha requires the GD extension')]);
        }

        return $this->success($data);
    }
}
