package kr.co.metanet.myapp.web;

import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/** 오류 응답을 설계/공통/03 의 스키마 하나로 통일한다. */
@RestControllerAdvice
public class ApiExceptionHandler {

    /**
     * 검증 실패를 400 으로 변환한다.
     *
     * @param ex 예외
     * @return 오류 응답
     */
    @ExceptionHandler(ValidationException.class)
    public ResponseEntity<Map<String, String>> onValidation(ValidationException ex) {
        return ResponseEntity.badRequest().body(Map.of("error", ex.getMessage()));
    }

    /**
     * JSON 파싱 실패도 검증 실패와 같은 메시지로 돌려준다.
     *
     * @param ex 예외
     * @return 오류 응답
     */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<Map<String, String>> onUnreadable(HttpMessageNotReadableException ex) {
        return ResponseEntity.badRequest()
                .body(Map.of("error", "title 은 필수이며 빈 문자열일 수 없습니다."));
    }

    /**
     * 그 밖의 예외는 500 으로 처리하되 내부 메시지를 노출하지 않는다.
     *
     * @param ex 예외
     * @return 오류 응답
     */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, String>> onOther(Exception ex) {
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "처리 중 오류가 발생했습니다."));
    }
}
