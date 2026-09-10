const { Client } = require('@notionhq/client');
const { getSecret } = require('./secrets');

class NotionApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function textBlock(type, content) {
  const rich = [{ type: 'text', text: { content: content.slice(0, 2000) } }];
  return { object: 'block', type, [type]: { rich_text: rich } };
}

// 간단한 마크다운 -> Notion 블록 변환 (제목/불릿/일반 문단만 지원, 표는 문단으로 폴백)
function markdownToBlocks(md) {
  const lines = md.split('\n');
  const blocks = [];
  for (const raw of lines) {
    const line = raw.trimEnd();
    if (!line.trim()) continue;
    if (line.startsWith('## ')) blocks.push(textBlock('heading_2', line.slice(3)));
    else if (line.startsWith('# ')) blocks.push(textBlock('heading_1', line.slice(2)));
    else if (line.startsWith('- ')) blocks.push(textBlock('bulleted_list_item', line.slice(2)));
    else if (line.startsWith('|')) blocks.push(textBlock('paragraph', line));
    else if (line.startsWith('>')) blocks.push(textBlock('quote', line.slice(1).trim()));
    else blocks.push(textBlock('paragraph', line));
  }
  return blocks.slice(0, 100); // Notion API 1회 요청 최대 100블록 제한
}

async function uploadReportToNotion({ title, markdown }) {
  // env(k8s Secret)에 있으면 그대로, 없고 워크로드 ID가 있으면 Key Vault에서 직접 — 환경이 스스로 고른다.
  const [token, parentPageId] = await Promise.all([
    getSecret('NOTION_TOKEN', 'notion-token'),
    getSecret('NOTION_PARENT_PAGE_ID', 'notion-parent-page-id'),
  ]);

  if (!token || !parentPageId) {
    throw new NotionApiError(
      401,
      'Notion 설정이 비어 있습니다. .env의 NOTION_TOKEN, NOTION_PARENT_PAGE_ID 설정을 확인하세요.'
    );
  }

  const notion = new Client({ auth: token });

  try {
    const page = await notion.pages.create({
      parent: { page_id: parentPageId },
      properties: {
        title: { title: [{ type: 'text', text: { content: title } }] },
      },
      children: markdownToBlocks(markdown),
    });
    return { pageId: page.id, url: page.url };
  } catch (err) {
    const status = err.status || 502;
    if (status === 401) {
      throw new NotionApiError(401, 'Notion 인증에 실패했습니다(401). NOTION_TOKEN 설정을 확인하세요.');
    }
    if (status === 403) {
      throw new NotionApiError(
        403,
        'Notion 접근 권한이 없습니다(403). 대상 페이지가 이 Integration과 Connect 되어 있는지 확인하세요.'
      );
    }
    throw new NotionApiError(status, `Notion 업로드 중 오류가 발생했습니다: ${err.message}`);
  }
}

module.exports = { uploadReportToNotion, NotionApiError };
