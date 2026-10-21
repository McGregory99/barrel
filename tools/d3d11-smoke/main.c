/*
 * D3D11 smoke test: creates a window and swapchain, presents FRAMES cleared frames,
 * and writes the adapter name, feature level and result to the file given as argv[1]
 * (default: d3d11-smoke.txt). Exit code 0 means every Present succeeded.
 */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>

#define FRAMES 120

static LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

int main(int argc, char **argv)
{
    const char *log_path = argc > 1 ? argv[1] : "d3d11-smoke.txt";
    FILE *log = fopen(log_path, "w");
    WNDCLASSW wc = {0};
    DXGI_SWAP_CHAIN_DESC desc = {0};
    IDXGISwapChain *swapchain = NULL;
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    ID3D11Texture2D *backbuffer = NULL;
    ID3D11RenderTargetView *rtv = NULL;
    IDXGIDevice *dxgi_device = NULL;
    IDXGIAdapter *adapter = NULL;
    DXGI_ADAPTER_DESC adapter_desc;
    D3D_FEATURE_LEVEL level;
    HRESULT hr;
    HWND hwnd;
    int frame, failed = 0;

    if (!log) return 2;

    wc.lpfnWndProc = window_proc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"d3d11_smoke";
    RegisterClassW(&wc);
    hwnd = CreateWindowW(L"d3d11_smoke", L"D3D11 smoke test", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                         100, 100, 640, 480, NULL, NULL, wc.hInstance, NULL);

    desc.BufferCount = 2;
    desc.BufferDesc.Width = 640;
    desc.BufferDesc.Height = 480;
    desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.OutputWindow = hwnd;
    desc.SampleDesc.Count = 1;
    desc.Windowed = TRUE;
    desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION,
                                       &desc, &swapchain, &device, &level, &context);
    if (FAILED(hr))
    {
        fprintf(log, "result: FAIL create device hr=0x%08lx\n", hr);
        fclose(log);
        return 1;
    }

    if (SUCCEEDED(ID3D11Device_QueryInterface(device, &IID_IDXGIDevice, (void **)&dxgi_device)) &&
        SUCCEEDED(IDXGIDevice_GetAdapter(dxgi_device, &adapter)) &&
        SUCCEEDED(IDXGIAdapter_GetDesc(adapter, &adapter_desc)))
        fprintf(log, "adapter: %ls\n", adapter_desc.Description);
    fprintf(log, "feature_level: 0x%x\n", level);

    IDXGISwapChain_GetBuffer(swapchain, 0, &IID_ID3D11Texture2D, (void **)&backbuffer);
    ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)backbuffer, NULL, &rtv);

    for (frame = 0; frame < FRAMES; frame++)
    {
        float color[4] = {0.1f, (float)frame / FRAMES, 0.4f, 1.0f};
        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) DispatchMessageW(&msg);
        ID3D11DeviceContext_OMSetRenderTargets(context, 1, &rtv, NULL);
        ID3D11DeviceContext_ClearRenderTargetView(context, rtv, color);
        if (FAILED(hr = IDXGISwapChain_Present(swapchain, 1, 0)))
        {
            fprintf(log, "present_failed: frame %d hr=0x%08lx\n", frame, hr);
            failed = 1;
            break;
        }
    }
    fprintf(log, "frames: %d\nresult: %s\n", frame, failed ? "FAIL" : "OK");
    fclose(log);
    return failed;
}
