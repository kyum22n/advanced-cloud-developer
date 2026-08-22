package kr.co.metanet.myapp.web;

/** 입력 검증 실패. 400 으로 매핑된다. */
public class ValidationException extends RuntimeException {

    private static final long serialVersionUID = 1L;

    public ValidationException(String message) {
        super(message);
    }
}
