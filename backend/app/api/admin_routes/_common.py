from __future__ import annotations

from typing import Annotated

from fastapi import Query
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession


class PageParams(BaseModel):
    page: int = 1
    page_size: int = 25
    q: str | None = None

    @property
    def offset(self) -> int:
        return (self.page - 1) * self.page_size


def page_params(
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=200)] = 25,
    q: Annotated[str | None, Query(max_length=100)] = None,
) -> PageParams:
    return PageParams(page=page, page_size=page_size, q=(q or None))


async def paginate(db: AsyncSession, stmt, p: PageParams) -> tuple[list, int]:
    total = await db.scalar(select(func.count()).select_from(stmt.order_by(None).subquery())) or 0
    rows = (await db.execute(stmt.offset(p.offset).limit(p.page_size))).scalars().unique().all()
    return list(rows), int(total)


def page_out(items: list, total: int, p: PageParams) -> dict:
    return {"items": items, "page": p.page, "page_size": p.page_size, "total": total}
