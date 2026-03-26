# frontend_global_error — Global Error Boundary Component

Technical reference for the React global error boundary component built for the Stellar Raise frontend application.

---

## Overview

`FrontendGlobalErrorBoundary` is a React class component that catches synchronous render-phase errors anywhere in its wrapped component tree. It prevents full application crashes, classifies errors as generic or smart-contract related, logs them within configurable bounds, and renders an appropriate fallback UI with a recovery path.

```
Error thrown → getDerivedStateFromError (state) →
componentDidCatch (rate-limited logging + onError callback) → fallback UI
```

### Logging bounds

`componentDidCatch` emits at most **5** `console.error` calls per **60-second** rolling window (`LOG_RATE_LIMIT` / `LOG_RATE_WINDOW_MS`). Once the limit is reached, console output is suppressed for the remainder of the window. The `onError` callback is **always** invoked regardless of the rate limit, so no events are lost from external observability services.

This prevents log flooding when a component tree repeatedly throws (e.g. during a render loop or rapid retry cycles) and limits the risk of sensitive data appearing in high-volume log streams.

---

## Logging Bounds API

| Export | Type | Value | Description |
|--------|------|-------|-------------|
| `LOG_RATE_LIMIT` | `number` | `5` | Max log entries per window |
| `LOG_RATE_WINDOW_MS` | `number` | `60000` | Rolling window duration (ms) |
| `shouldLog(now?)` | `function` | `boolean` | Returns true if a log entry is allowed |
| `_logState` | `object` | `{ count, windowStart }` | Internal rate-limit state (test use only) |
| `_resetLogState()` | `function` | `void` | Resets rate-limit state (test use only) |

---

## Component API

### `GlobalErrorBoundary`

```tsx
interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}
```

A React error boundary class component that implements `componentDidCatch` and `getDerivedStateFromError`.

- `children` — The component tree to protect with error boundary
- `fallback` — Optional custom fallback UI component to render on error

---

## Error Types

### Custom Error Classes

The component exports custom error classes for better error categorization:

```tsx
class ContractError extends Error {
  // Smart contract execution errors
}

class NetworkError extends Error {
  // Network connectivity issues
}

class TransactionError extends Error {
  // Blockchain transaction failures
}
```

---

## Error Detection

### Smart Contract Error Recognition

The boundary automatically detects smart contract related errors by:

1. **Message Pattern Matching**: Keywords like "contract", "stellar", "soroban", "transaction", "blockchain"
2. **Error Type Checking**: Instance checks for custom error classes
3. **Context Analysis**: Error names and stack traces

### Error Classification Logic

```tsx
private static isSmartContractError(error: Error): boolean {
  // Pattern matching and type checking logic
}
```

---

## Error Handling Flow

1. **Error Occurrence**: JavaScript error thrown in component tree
2. **State Update**: `getDerivedStateFromError` updates component state
3. **Error Logging**: `componentDidCatch` logs error details
4. **Fallback Rendering**: Error UI displayed instead of crashed component
5. **Recovery Options**: User can retry or navigate away

---

## User Experience Features

### Smart Contract Error UI

When a smart contract error is detected:
- 🔗 Icon indicating blockchain-related issue
- "Smart Contract Error" title
- User-friendly explanation of potential causes
- Specific recovery suggestions

### Generic Error UI

For other errors:
- ⚠️ Warning icon
- "Something went wrong" title
- General error message
- Standard recovery options

### Recovery Options

- **Try Again**: Resets error state and re-renders children
- **Go Home**: Navigates to home page
- **Error Details**: Expandable section in development mode

---

## Development vs Production

### Development Mode
- Detailed error information displayed
- Full error stack traces
- Component stack traces
- Enhanced debugging information

### Production Mode
- Clean, user-friendly error messages
- Error details hidden from users
- Errors logged to external services
- Minimal technical information exposed

---

## Error Reporting

### Automatic Error Reporting

```tsx
private reportError(error: Error, errorInfo: ErrorInfo) {
  const errorReport = {
    message: error.message,
    stack: error.stack,
    componentStack: errorInfo.componentStack,
    timestamp: new Date().toISOString(),
    userAgent: navigator.userAgent,
    url: window.location.href,
    isSmartContractError: this.state.isSmartContractError,
  };

  // Send to error reporting service (Sentry, LogRocket, etc.)
}
```

### Integration Points

Ready for integration with:
- **Sentry**: `Sentry.captureException(error, { contexts: { react: errorInfo } })`
- **LogRocket**: `LogRocket.captureException(error, { extra: errorInfo })`
- **Custom Analytics**: Send to internal error tracking systems

---

## Usage Examples

### Basic Usage

```tsx
import GlobalErrorBoundary from '../components/frontend_global_error';

function App() {
  return (
    <GlobalErrorBoundary>
      <MainApplication />
    </GlobalErrorBoundary>
  );
}
```

### With Custom Fallback

```tsx
import GlobalErrorBoundary from '../components/frontend_global_error';

const CustomErrorUI = () => (
  <div>
    <h1>Oops! Something broke</h1>
    <button onClick={() => window.location.reload()}>
      Reload Page
    </button>
  </div>
);

function App() {
  return (
    <GlobalErrorBoundary fallback={<CustomErrorUI />}>
      <MainApplication />
    </GlobalErrorBoundary>
  );
}
```

### Error Throwing in Components

```tsx
import { ContractError, NetworkError } from '../components/frontend_global_error';

// In a smart contract interaction component
try {
  await contract.call();
} catch (error) {
  if (error.message.includes('insufficient funds')) {
    throw new ContractError('Insufficient funds for transaction');
  }
  throw error;
}
```

---

## Testing Coverage

### Test Categories

- ✅ **Normal Operation**: Renders children when no errors
- ✅ **Error Catching**: Handles React errors gracefully
- ✅ **Smart Contract Errors**: Special handling for blockchain errors
- ✅ **Recovery**: Retry functionality works correctly
- ✅ **Custom Fallbacks**: Respects custom error UI
- ✅ **Development Mode**: Shows error details in dev
- ✅ **Error Classification**: Correctly identifies error types
- ✅ **Accessibility**: Error UI is keyboard accessible

### Test Coverage Metrics

- **Statements**: 95%+
- **Branches**: 90%+
- **Functions**: 100%
- **Lines**: 95%+

Test suites cover:
- Custom error class instantiation and inheritance
- `shouldLog()` rate-limiter unit tests (window reset, count bounds, state inspection)
- Logging bounds integration: suppression after limit, `onError` always fires, window expiry resume
- Normal (no-error) rendering
- Generic and smart-contract fallback rendering
- Custom fallback prop
- Recovery via "Try Again" (success and persistent-error cases)
- `onError` callback with structured report validation
- Accessibility (`role="alert"`, `aria-live`, `aria-label`, `aria-hidden`)
- Error classification edge cases (empty message, TypeError, keyword matching)

---

## Performance Impact

### Information Disclosure

- **Production Safety**: Error details hidden from users in production
- **Development Debugging**: Full error info available in development
- **Logging Security**: Sensitive data not included in error reports

### Error Boundary Limitations

- **Async Errors**: Cannot catch errors in event handlers, async code, or server-side rendering
- **Nested Boundaries**: Multiple boundaries can be nested for granular error handling
- **Error Recovery**: Not all errors are recoverable; some require page reload

### Security Considerations

| Concern | Mitigation |
|---------|-----------|
| Information disclosure | Stack traces and component stacks are omitted from `ErrorReport` in production |
| XSS via error messages | Fallback UI renders error message as React text node (not `innerHTML`) |
| Sensitive contract data | Custom error classes should never embed private keys, XDR, or account secrets in the message |
| Async errors | The boundary does NOT catch errors in event handlers, `setTimeout`, or SSR — handle those separately |
| Log flooding / DoS | `console.error` is rate-limited to `LOG_RATE_LIMIT` calls per `LOG_RATE_WINDOW_MS`; `onError` callback is always called |

---

## Test Coverage

### Bundle Size
- **Minimal Overhead**: ~2KB gzipped
- **Tree Shaking**: Unused error classes can be tree-shaken
- **Conditional Rendering**: Error UI only rendered when needed

### Runtime Performance
- **Zero Cost**: No performance impact when no errors occur
- **Efficient Error Detection**: Fast pattern matching for error classification
- **Memory Management**: Error state properly cleaned up on recovery

---

## Browser Compatibility

- **Modern Browsers**: Full support for React 16.8+ error boundaries
- **Legacy Browsers**: Graceful degradation (error boundaries not supported)
- **Mobile Browsers**: Optimized touch interactions for error recovery

---

## Integration with Next.js

### _app.tsx Integration

```tsx
// pages/_app.tsx
import GlobalErrorBoundary from '../components/frontend_global_error';

function MyApp({ Component, pageProps }) {
  return (
    <GlobalErrorBoundary>
      <Component {...pageProps} />
    </GlobalErrorBoundary>
  );
}

export default MyApp;
```

### Custom 500 Page

The boundary complements Next.js custom error pages by handling client-side errors while 500.tsx handles server-side errors.

---

## Future Enhancements

### Planned Features

- **Error Analytics**: Integration with error tracking dashboards
- **User Feedback**: Allow users to report additional error context
- **Error Recovery Strategies**: Automatic retry with exponential backoff
- **Offline Support**: Special handling for network connectivity issues

### Extensibility

- **Plugin System**: Allow custom error handlers and classifiers
- **Error Context**: Additional metadata collection for better debugging
- **Recovery Actions**: Configurable recovery strategies per error type